defmodule Tinkex.CheckpointDownloadTest do
  use Tinkex.HTTPCase, async: true

  alias Tinkex.{CheckpointDownload, RestClient}

  setup :setup_http_client

  setup %{config: config} do
    # Create temp directory for downloads
    tmp_dir = System.tmp_dir!() |> Path.join("tinkex_test_#{:rand.uniform(100_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    client = RestClient.new("session-123", config)
    {:ok, client: client, tmp_dir: tmp_dir}
  end

  describe "download/3" do
    test "downloads and extracts checkpoint", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      # Create a test tar file
      tar_content = create_test_tar()

      # Stub get_checkpoint_archive_url
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "#{endpoint_url(bypass)}/download/ckpt.tar")
          |> Plug.Conn.resp(302, "")
        end
      )

      # Stub actual download
      Bypass.expect_once(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.put_resp_header("content-length", "#{byte_size(tar_content)}")
        |> Plug.Conn.resp(200, tar_content)
      end)

      {:ok, result} =
        CheckpointDownload.download(
          client,
          "tinker://run-123/weights/0001",
          output_dir: tmp_dir
        )

      assert result.destination =~ "run-123_weights_0001"
      assert result.checkpoint_path == "tinker://run-123/weights/0001"
      assert File.exists?(result.destination)
    end

    test "returns error when target exists and force=false", %{client: client, tmp_dir: tmp_dir} do
      # Create existing directory
      existing_dir = Path.join(tmp_dir, "run-123_weights_0001")
      File.mkdir_p!(existing_dir)

      {:error, {:exists, path}} =
        CheckpointDownload.download(
          client,
          "tinker://run-123/weights/0001",
          output_dir: tmp_dir
        )

      assert path == existing_dir
    end

    test "overwrites when force=true", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      tar_content = create_test_tar()

      # Create existing directory with a file
      existing_dir = Path.join(tmp_dir, "run-123_weights_0001")
      File.mkdir_p!(existing_dir)
      File.write!(Path.join(existing_dir, "old_file.txt"), "old content")

      # Stubs
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "#{endpoint_url(bypass)}/download/ckpt.tar")
          |> Plug.Conn.resp(302, "")
        end
      )

      Bypass.expect_once(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.resp(200, tar_content)
      end)

      {:ok, result} =
        CheckpointDownload.download(
          client,
          "tinker://run-123/weights/0001",
          output_dir: tmp_dir,
          force: true
        )

      # Old file should be gone
      refute File.exists?(Path.join(result.destination, "old_file.txt"))
      # New file from tar should exist
      assert File.exists?(Path.join(result.destination, "test_file.txt"))
    end

    test "returns error on invalid checkpoint path", %{client: client, tmp_dir: tmp_dir} do
      {:error, {:invalid_path, _}} =
        CheckpointDownload.download(
          client,
          "invalid-path",
          output_dir: tmp_dir
        )
    end

    test "returns error when checkpoint not found", %{
      bypass: bypass,
      client: client,
      tmp_dir: tmp_dir
    } do
      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/9999/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.resp(404, ~s({"error": "Not found"}))
        end
      )

      {:error, error} =
        CheckpointDownload.download(
          client,
          "tinker://run-123/weights/9999",
          output_dir: tmp_dir
        )

      assert error.status == 404
    end

    test "reports progress via callback", %{bypass: bypass, client: client, tmp_dir: tmp_dir} do
      tar_content = create_test_tar()
      test_pid = self()

      Bypass.expect_once(
        bypass,
        "GET",
        "/api/v1/training_runs/run-123/checkpoints/weights/0001/archive",
        fn conn ->
          conn
          |> Plug.Conn.put_resp_header("location", "#{endpoint_url(bypass)}/download/ckpt.tar")
          |> Plug.Conn.resp(302, "")
        end
      )

      Bypass.expect_once(bypass, "GET", "/download/ckpt.tar", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/octet-stream")
        |> Plug.Conn.put_resp_header("content-length", "#{byte_size(tar_content)}")
        |> Plug.Conn.resp(200, tar_content)
      end)

      progress_fn = fn downloaded, total ->
        send(test_pid, {:progress, downloaded, total})
      end

      {:ok, _} =
        CheckpointDownload.download(
          client,
          "tinker://run-123/weights/0001",
          output_dir: tmp_dir,
          progress: progress_fn
        )

      assert_receive {:progress, _, _}, 1000
    end
  end

  # Helper to create a test tar archive
  defp create_test_tar do
    tmp_dir = System.tmp_dir!()
    tmp_file = Path.join(tmp_dir, "test_file.txt")
    File.write!(tmp_file, "test content from checkpoint")

    tar_path = Path.join(tmp_dir, "test_#{:rand.uniform(100_000)}.tar")

    :erl_tar.create(
      String.to_charlist(tar_path),
      [{~c"test_file.txt", String.to_charlist(tmp_file)}]
    )

    content = File.read!(tar_path)
    File.rm!(tmp_file)
    File.rm!(tar_path)
    content
  end
end
