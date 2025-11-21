defmodule Tinkex.Types.SessionResponsesTest do
  use ExUnit.Case, async: true

  alias Tinkex.Types.{GetSessionResponse, ListSessionsResponse}

  describe "GetSessionResponse" do
    test "creates struct with training_run_ids and sampler_ids" do
      response = %GetSessionResponse{
        training_run_ids: ["model-1", "model-2"],
        sampler_ids: ["sampler-1"]
      }

      assert response.training_run_ids == ["model-1", "model-2"]
      assert response.sampler_ids == ["sampler-1"]
    end

    test "handles empty lists" do
      response = %GetSessionResponse{
        training_run_ids: [],
        sampler_ids: []
      }

      assert response.training_run_ids == []
      assert response.sampler_ids == []
    end

    test "from_map/1 converts string-keyed map to struct" do
      map = %{
        "training_run_ids" => ["model-1"],
        "sampler_ids" => ["sampler-1", "sampler-2"]
      }

      response = GetSessionResponse.from_map(map)

      assert response.training_run_ids == ["model-1"]
      assert response.sampler_ids == ["sampler-1", "sampler-2"]
    end

    test "from_map/1 converts atom-keyed map to struct" do
      map = %{
        training_run_ids: ["model-1"],
        sampler_ids: ["sampler-1"]
      }

      response = GetSessionResponse.from_map(map)

      assert response.training_run_ids == ["model-1"]
      assert response.sampler_ids == ["sampler-1"]
    end
  end

  describe "ListSessionsResponse" do
    test "creates struct with sessions list" do
      response = %ListSessionsResponse{
        sessions: ["session-1", "session-2", "session-3"]
      }

      assert length(response.sessions) == 3
      assert "session-1" in response.sessions
    end

    test "handles empty sessions list" do
      response = %ListSessionsResponse{sessions: []}
      assert response.sessions == []
    end

    test "from_map/1 converts map to struct" do
      map = %{"sessions" => ["session-1", "session-2"]}

      response = ListSessionsResponse.from_map(map)

      assert response.sessions == ["session-1", "session-2"]
    end
  end
end
