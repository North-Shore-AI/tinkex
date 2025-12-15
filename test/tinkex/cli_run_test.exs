defmodule Tinkex.CLIRunTest do
  use Supertester.ExUnitFoundation, isolation: :full_isolation

  import ExUnit.CaptureIO

  alias Tinkex.CLI
  alias Tinkex.Types.{SampleResponse, SampledSequence, SamplingParams}

  defmodule ServiceStub do
    def start_link(opts) do
      send(self(), {:service_started, opts})
      {:ok, {:service_stub, opts}}
    end

    def create_sampling_client(service, opts) do
      send(self(), {:sampling_client_created, service, opts})
      {:ok, {:sampling_stub, service, opts}}
    end
  end

  defmodule SamplingStub do
    def sample(client, prompt, params, opts) do
      send(self(), {:sample_called, client, prompt, params, opts})
      task = Task.async(fn -> {:ok, sample_response()} end)
      {:ok, task}
    end

    defp sample_response do
      %SampleResponse{
        sequences: [%SampledSequence{tokens: [1, 2, 3], logprobs: [0.1, 0.2], stop_reason: :stop}],
        prompt_logprobs: nil,
        topk_prompt_logprobs: nil,
        type: "sample"
      }
    end
  end

  defmodule ModelInputStub do
    def from_text(text, opts) do
      send(self(), {:encode_called, text, opts})
      {:ok, {:model_input, text}}
    end

    def from_ints(tokens) do
      send(self(), {:from_ints_called, tokens})
      {:model_input, tokens}
    end
  end

  defmodule TokenizerStub do
    def decode(tokens, model_name) do
      send(self(), {:decode_called, tokens, model_name})
      {:ok, "decoded:#{Enum.join(tokens, ",")}"}
    end
  end

  setup do
    Application.put_env(:tinkex, :cli_run_deps, %{
      service_client_module: ServiceStub,
      sampling_client_module: SamplingStub,
      model_input_module: ModelInputStub,
      tokenizer_module: TokenizerStub
    })

    on_exit(fn -> Application.delete_env(:tinkex, :cli_run_deps) end)
    :ok
  end

  test "runs sampling with prompt text and prints decoded output" do
    args = [
      "run",
      "--base-model",
      "Qwen/Qwen2.5-7B",
      "--prompt",
      "hello",
      "--max-tokens",
      "16",
      "--top-p",
      "0.9",
      "--num-samples",
      "2",
      "--api-key",
      "tml-test-key"
    ]

    output =
      capture_io(fn ->
        assert {:ok, %{command: :run, response: %SampleResponse{} = response}} = CLI.run(args)
        assert length(response.sequences) == 1
      end)

    assert output =~ "Starting sampling"
    assert output =~ "Sample 1:"
    assert output =~ "decoded:1,2,3"
    assert output =~ "stop_reason"

    assert_receive {:service_started, _opts}
    assert_receive {:sampling_client_created, {:service_stub, _}, sampling_opts}
    assert sampling_opts[:base_model] == "Qwen/Qwen2.5-7B"

    assert_receive {:encode_called, "hello", [model_name: "Qwen/Qwen2.5-7B"]}

    assert_receive {:sample_called, {:sampling_stub, _, _}, {:model_input, "hello"},
                    %SamplingParams{max_tokens: 16, top_p: top_p}, sample_opts}

    assert_in_delta top_p, 0.9, 0.001
    assert Keyword.get(sample_opts, :num_samples) == 2
  end

  test "loads prompt from file and writes JSON output" do
    prompt_path =
      Path.join(
        System.tmp_dir!(),
        "tinkex_cli_run_prompt_#{System.unique_integer([:positive])}.json"
      )

    output_path =
      Path.join(
        System.tmp_dir!(),
        "tinkex_cli_run_output_#{System.unique_integer([:positive])}.json"
      )

    File.write!(prompt_path, "[7,8]")

    args = [
      "run",
      "--model-path",
      "local-model",
      "--prompt-file",
      prompt_path,
      "--json",
      "--output",
      output_path,
      "--api-key",
      "tml-test-key"
    ]

    output =
      capture_io(fn ->
        assert {:ok, %{command: :run, response: %SampleResponse{}}} = CLI.run(args)
      end)

    assert output =~ "Starting sampling"
    assert_receive {:from_ints_called, [7, 8]}

    assert File.exists?(output_path)

    {:ok, written} = File.read(output_path)
    {:ok, parsed} = Jason.decode(written)

    assert parsed["type"] == "sample"
    assert [%{"tokens" => [1, 2, 3], "stop_reason" => "stop"}] = parsed["sequences"]
  end

  test "errors when prompt options conflict" do
    stderr =
      capture_io(:stderr, fn ->
        assert {:error, %Tinkex.Error{category: :user}} =
                 CLI.run([
                   "run",
                   "--base-model",
                   "model",
                   "--prompt",
                   "hi",
                   "--prompt-file",
                   "path"
                 ])
      end)

    assert stderr =~ "--prompt and --prompt-file"
  end
end
