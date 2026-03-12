defmodule Tinkex.HuggingFaceTest do
  use ExUnit.Case, async: true

  alias Tinkex.HuggingFace

  defmodule RestClientStub do
    def get_checkpoint_archive_url_by_tinker_path(_client, _path) do
      {:ok, %{url: Process.get(:archive_url)}}
    end

    def get_weights_info_by_tinker_path(_client, _path) do
      {:ok,
       %Tinkex.Types.WeightsInfoResponse{
         base_model: "meta-llama/Llama-3.1-8B",
         is_lora: true,
         lora_rank: 16,
         train_attn: true,
         train_mlp: false,
         train_unembed: true
       }}
    end
  end

  test "resolve_token prefers cli token, then env, then token file" do
    tmp_dir = tmp_dir!()
    token_path = Path.join(tmp_dir, "hf-token")
    File.write!(token_path, "file-token\n")

    assert {:ok, "cli-token"} =
             HuggingFace.resolve_token(
               hf_token: "cli-token",
               env: %{"HF_TOKEN" => "env-token"},
               token_path: token_path
             )

    assert {:ok, "env-token"} =
             HuggingFace.resolve_token(
               env: %{"HF_TOKEN" => "env-token"},
               token_path: token_path
             )

    assert {:ok, "alt-env-token"} =
             HuggingFace.resolve_token(
               env: %{"HUGGING_FACE_HUB_TOKEN" => "alt-env-token"},
               token_path: token_path
             )

    assert {:ok, "file-token"} =
             HuggingFace.resolve_token(
               env: %{},
               token_path: token_path
             )
  end

  test "push_checkpoint_adapter uploads adapter files with lfs and model card" do
    bypass = Bypass.open()
    archive_path = create_checkpoint_archive!()

    Process.put(:archive_url, "http://localhost:#{bypass.port}/archive.tar")

    on_exit(fn ->
      Process.delete(:archive_url)
      File.rm_rf!(Path.dirname(archive_path))
    end)

    agent = start_supervised!({Agent, fn -> %{uploaded: nil, commit_lines: nil} end})

    Bypass.expect_once(bypass, "GET", "/api/whoami-v2", fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"name":"coder"}))
    end)

    Bypass.expect_once(bypass, "GET", "/archive.tar", fn conn ->
      conn
      |> Plug.Conn.put_resp_header("content-type", "application/x-tar")
      |> Plug.Conn.resp(200, File.read!(archive_path))
    end)

    Bypass.expect_once(bypass, "POST", "/api/repos/create", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"name" => "adapter-repo", "private" => true}
      assert get_req_header(conn, "authorization") == ["Bearer hf_test_token"]

      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.resp(200, ~s({"url":"http://localhost:#{bypass.port}/coder/adapter-repo"}))
    end)

    Bypass.expect_once(bypass, "GET", "/coder/adapter-repo/resolve/branch-1/README.md", fn conn ->
      Plug.Conn.resp(conn, 404, "Not found")
    end)

    Bypass.expect_once(
      bypass,
      "POST",
      "/api/models/coder/adapter-repo/preupload/branch-1",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        uploaded_paths =
          payload["files"]
          |> Enum.map(& &1["path"])
          |> Enum.sort()

        assert uploaded_paths == ["README.md", "adapter_config.json", "adapter_model.safetensors"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "files" => [
              %{"path" => "README.md", "uploadMode" => "regular", "shouldIgnore" => false},
              %{
                "path" => "adapter_config.json",
                "uploadMode" => "regular",
                "shouldIgnore" => false
              },
              %{
                "path" => "adapter_model.safetensors",
                "uploadMode" => "lfs",
                "shouldIgnore" => false
              }
            ]
          })
        )
      end
    )

    Bypass.expect_once(
      bypass,
      "POST",
      "/coder/adapter-repo.git/info/lfs/objects/batch",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        payload = Jason.decode!(body)

        assert payload["operation"] == "upload"
        assert length(payload["objects"]) == 1

        oid = hd(payload["objects"])["oid"]
        size = hd(payload["objects"])["size"]

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(
          200,
          Jason.encode!(%{
            "objects" => [
              %{
                "oid" => oid,
                "size" => size,
                "actions" => %{
                  "upload" => %{
                    "href" => "http://localhost:#{bypass.port}/lfs/upload"
                  },
                  "verify" => %{
                    "href" => "http://localhost:#{bypass.port}/lfs/verify"
                  }
                }
              }
            ]
          })
        )
      end
    )

    Bypass.expect_once(bypass, "PUT", "/lfs/upload", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Agent.update(agent, &Map.put(&1, :uploaded, body))

      conn
      |> Plug.Conn.put_resp_header("etag", "\"part-1\"")
      |> Plug.Conn.resp(200, "")
    end)

    Bypass.expect_once(bypass, "POST", "/lfs/verify", fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      payload = Jason.decode!(body)
      assert is_binary(payload["oid"])
      assert is_integer(payload["size"])
      Plug.Conn.resp(conn, 200, "{}")
    end)

    Bypass.expect_once(
      bypass,
      "POST",
      "/api/models/coder/adapter-repo/commit/branch-1",
      fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        lines = body |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
        Agent.update(agent, &Map.put(&1, :commit_lines, lines))

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.resp(200, ~s({"commit":{"oid":"abc123"}}))
      end
    )

    assert {:ok, %{repo_id: "coder/adapter-repo", revision: "branch-1", public: false}} =
             HuggingFace.push_checkpoint_adapter(
               :rest_client,
               "tinker://run-a/weights/0001",
               rest_client_module: RestClientStub,
               endpoint: "http://localhost:#{bypass.port}",
               repo_id: "adapter-repo",
               revision: "branch-1",
               hf_token: "hf_test_token"
             )

    %{uploaded: uploaded, commit_lines: commit_lines} = Agent.get(agent, & &1)
    assert uploaded == "weights-binary"

    assert [%{"key" => "header"} | operations] = commit_lines

    assert Enum.any?(operations, fn line ->
             line["key"] == "lfsFile" and line["value"]["path"] == "adapter_model.safetensors"
           end)

    assert Enum.any?(operations, fn line ->
             line["key"] == "file" and line["value"]["path"] == "adapter_config.json"
           end)

    assert Enum.any?(operations, fn line ->
             line["key"] == "file" and line["value"]["path"] == "README.md"
           end)

    refute Enum.any?(operations, fn line ->
             line["value"]["path"] == "checkpoint_complete"
           end)
  end

  defp create_checkpoint_archive! do
    tmp_dir = tmp_dir!()
    extract_dir = Path.join(tmp_dir, "extract")
    File.mkdir_p!(extract_dir)

    File.write!(
      Path.join(extract_dir, "adapter_config.json"),
      Jason.encode!(%{"peft_type" => "LORA"}) <> "\n"
    )

    File.write!(Path.join(extract_dir, "adapter_model.safetensors"), "weights-binary")
    File.write!(Path.join(extract_dir, "checkpoint_complete"), "ok")

    archive_path = Path.join(tmp_dir, "checkpoint.tar")

    :ok =
      :erl_tar.create(
        String.to_charlist(archive_path),
        [
          {~c"adapter_config.json", File.read!(Path.join(extract_dir, "adapter_config.json"))},
          {~c"adapter_model.safetensors",
           File.read!(Path.join(extract_dir, "adapter_model.safetensors"))},
          {~c"checkpoint_complete", File.read!(Path.join(extract_dir, "checkpoint_complete"))}
        ]
      )

    archive_path
  end

  defp get_req_header(conn, key), do: Plug.Conn.get_req_header(conn, key)

  defp tmp_dir! do
    path = Path.join(System.tmp_dir!(), "tinkex_hf_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    path
  end
end
