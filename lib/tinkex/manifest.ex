defmodule Tinkex.Manifest do
  @moduledoc """
  Loads the Tinkex API manifest for Pristine runtime execution.
  """

  @manifest_path Path.expand("manifest.yaml", __DIR__)
  @external_resource @manifest_path

  @manifest (case Pristine.Manifest.load_file(@manifest_path) do
               {:ok, manifest} ->
                 manifest

               {:error, errors} ->
                 raise ArgumentError,
                       "failed to load manifest at #{@manifest_path}: #{inspect(errors)}"
             end)

  @spec load!() :: Pristine.Manifest.t()
  def load!, do: @manifest
end
