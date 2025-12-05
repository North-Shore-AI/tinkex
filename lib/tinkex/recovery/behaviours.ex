defmodule Tinkex.Recovery.RestBehaviour do
  @moduledoc false

  @callback get_training_run(Tinkex.Config.t(), String.t()) ::
              {:ok, Tinkex.Types.TrainingRun.t()} | {:error, term()}
end

defmodule Tinkex.Recovery.ServiceClientBehaviour do
  @moduledoc false

  @callback create_rest_client(pid()) :: {:ok, Tinkex.RestClient.t()} | {:error, term()}

  @callback create_training_client_from_state(pid(), String.t(), keyword()) ::
              {:ok, pid()} | {:error, term()}

  @callback create_training_client_from_state_with_optimizer(pid(), String.t(), keyword()) ::
              {:ok, pid()} | {:error, term()}
end
