defmodule Tinkex.TrainingClientTokenizerTest do
  use ExUnit.Case, async: true

  alias Tinkex.TrainingClient
  alias Tinkex.Types.GetInfoResponse

  # Mock tokenizer module for testing
  defmodule MockTokenizer do
    defstruct [:id]

    def encode(%__MODULE__{id: id}, text) do
      # Return deterministic tokens based on id and text
      {:ok, %{ids: [String.length(text), String.length(id)]}}
    end

    def decode(%__MODULE__{id: id}, _ids) do
      {:ok, "decoded-#{id}"}
    end
  end

  # Mock load function that returns our test tokenizer (arity 2 for opts)
  defp mock_load_fun(tokenizer_id, _opts) do
    {:ok, %MockTokenizer{id: tokenizer_id}}
  end

  # Create a mock GetInfoResponse
  defp mock_info_response(base_model, tokenizer_id \\ nil) do
    %GetInfoResponse{
      model_id: "model-123",
      model_data: %{
        base_model: base_model,
        tokenizer_id: tokenizer_id
      }
    }
  end

  describe "get_tokenizer/2" do
    test "fetches tokenizer using model info" do
      # Use unique model name to avoid cache pollution with other tests
      unique_model = "test-model-fetch-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok, mock_info_response(unique_model)}
      end

      # Use a stub client (we're using info_fun to bypass GenServer)
      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: ^unique_model}} = result
    end

    test "uses tokenizer_id from model_data when available" do
      unique_tokenizer = "custom-tokenizer-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok, mock_info_response("base-model-unused", unique_tokenizer)}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: ^unique_tokenizer}} = result
    end

    test "applies Llama-3 heuristic" do
      # Llama-3 model names should use the workaround tokenizer
      info_fun = fn _client ->
        {:ok, mock_info_response("meta-llama/Llama-3-8B-Test")}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      # Should use the Llama-3 workaround tokenizer
      assert {:ok, %MockTokenizer{id: "baseten/Meta-Llama-3-tokenizer"}} = result
    end

    test "propagates info fetch errors" do
      info_fun = fn _client ->
        {:error, %Tinkex.Error{type: :network_error, message: "Connection failed"}}
      end

      client = self()

      result = TrainingClient.get_tokenizer(client, info_fun: info_fun)

      assert {:error, %Tinkex.Error{type: :network_error}} = result
    end

    test "propagates tokenizer load errors" do
      unique_model = "nonexistent-model-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok, mock_info_response(unique_model)}
      end

      load_fun = fn _id, _opts ->
        {:error, %Tinkex.Error{type: :validation, message: "Tokenizer not found"}}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: load_fun
        )

      assert {:error, %Tinkex.Error{}} = result
    end
  end

  describe "encode/3" do
    test "propagates info fetch errors" do
      info_fun = fn _client ->
        {:error, %Tinkex.Error{type: :network_error, message: "Failed"}}
      end

      client = self()

      result = TrainingClient.encode(client, "test", info_fun: info_fun)

      assert {:error, %Tinkex.Error{type: :network_error}} = result
    end

    test "calls tokenizer encode with resolved model name" do
      # This test verifies that encode/3 correctly extracts the model name
      # and passes it to Tinkex.Tokenizer.encode. We use a unique model name
      # to avoid cache pollution with other tests.
      unique_model = "test-model-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok, mock_info_response(unique_model)}
      end

      # Create a load function that returns an error we can detect
      load_fun = fn tokenizer_id, _opts ->
        send(self(), {:load_called, tokenizer_id})
        {:error, %Tinkex.Error{type: :validation, message: "Test tokenizer not found"}}
      end

      client = self()

      result =
        TrainingClient.encode(client, "test",
          info_fun: info_fun,
          load_fun: load_fun
        )

      # Verify that load was called with the correct tokenizer ID
      assert_received {:load_called, ^unique_model}

      # Result should be an error from the load function
      assert {:error, %Tinkex.Error{}} = result
    end
  end

  describe "decode/3" do
    test "propagates info fetch errors" do
      info_fun = fn _client ->
        {:error, %Tinkex.Error{type: :timeout, message: "Timed out"}}
      end

      client = self()

      result = TrainingClient.decode(client, [1, 2, 3], info_fun: info_fun)

      assert {:error, %Tinkex.Error{type: :timeout}} = result
    end
  end

  describe "get_model_name_from_info/1 (via get_tokenizer)" do
    test "extracts base_model from GetInfoResponse" do
      unique_model = "extracted-model-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "m1",
           model_data: %{base_model: unique_model}
         }}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: ^unique_model}} = result
    end

    test "extracts model_name when base_model is nil" do
      unique_model = "fallback-model-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok,
         %GetInfoResponse{
           model_id: "m1",
           model_data: %{model_name: unique_model}
         }}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: ^unique_model}} = result
    end

    test "handles plain map responses" do
      unique_model = "map-model-#{System.unique_integer([:positive])}"

      info_fun = fn _client ->
        {:ok,
         %{
           model_id: "m1",
           model_data: %{base_model: unique_model}
         }}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: ^unique_model}} = result
    end

    test "defaults to 'unknown' when model info is incomplete" do
      info_fun = fn _client ->
        {:ok, %{model_id: "m1", model_data: %{}}}
      end

      client = self()

      result =
        TrainingClient.get_tokenizer(client,
          info_fun: info_fun,
          load_fun: &mock_load_fun/2
        )

      assert {:ok, %MockTokenizer{id: "unknown"}} = result
    end
  end
end
