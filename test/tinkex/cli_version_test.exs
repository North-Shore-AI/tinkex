defmodule Tinkex.CLIVersionTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI

  defmodule VersionStub do
    def spec(:tinkex, :vsn), do: ~c"9.9.9"
  end

  defmodule CommitStub do
    def cmd("git", ["rev-parse", "--short", "HEAD"]) do
      {"abc123\n", 0}
    end
  end

  defmodule MissingCommitStub do
    def cmd("git", ["rev-parse", "--short", "HEAD"]) do
      {"", 1}
    end
  end

  setup do
    on_exit(fn -> Application.delete_env(:tinkex, :cli_version_deps) end)
    :ok
  end

  test "prints version and commit when available" do
    Application.put_env(:tinkex, :cli_version_deps, %{
      app_module: VersionStub,
      system_module: CommitStub
    })

    output =
      capture_io(fn ->
        assert {:ok, %{version: "9.9.9", commit: "abc123"}} = CLI.run(["version"])
      end)

    assert String.trim(output) == "tinkex 9.9.9 (abc123)"
  end

  test "supports JSON output and omits commit when git is unavailable" do
    Application.put_env(:tinkex, :cli_version_deps, %{
      app_module: VersionStub,
      system_module: MissingCommitStub
    })

    output =
      capture_io(fn ->
        assert {:ok, %{commit: nil, options: %{json: true}}} = CLI.run(["version", "--json"])
      end)

    assert Jason.decode!(output) == %{"version" => "9.9.9", "commit" => nil}
  end

  test "accepts the reserved --deps flag without altering behavior" do
    Application.put_env(:tinkex, :cli_version_deps, %{
      app_module: VersionStub,
      system_module: MissingCommitStub
    })

    output =
      capture_io(fn ->
        assert {:ok, %{options: %{deps: true}}} = CLI.run(["version", "--deps"])
      end)

    assert String.trim(output) == "tinkex 9.9.9"
  end
end
