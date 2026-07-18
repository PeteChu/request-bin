defmodule RequestBin.RequestsTest do
  use RequestBin.DataCase, async: true

  alias RequestBin.Bins.Request
  alias RequestBin.Requests

  test "extracts exact JSON bytes and parses an object" do
    body = ~s({ "event" : "created" })
    assert_info(body, "application/json", %{"event" => "created"})
  end

  test "normalizes top-level JSON values into a map" do
    assert_info("[1,2]", "application/problem+json", %{"_json" => [1, 2]})
    assert_info("true", "application/json", %{"_json" => true})
  end

  test "marks malformed JSON without losing its bytes" do
    assert_info("{not-json", "Application/JSON; charset=utf-8", %{
      "_parse_error" => "invalid_json"
    })
  end

  test "parses valid URL-encoded bodies and marks invalid UTF-8" do
    assert_info("event=created&count=2", "application/x-www-form-urlencoded", %{
      "event" => "created",
      "count" => "2"
    })

    assert_info("event=%FF", "application/x-www-form-urlencoded", %{
      "_parse_error" => "invalid_urlencoded"
    })
  end

  test "preserves text and multipart bytes with no parsed representation" do
    assert_info("plain text", "text/plain", %{})

    assert_info(
      "--boundary\r\ncontent\r\n--boundary--",
      "multipart/form-data; boundary=boundary",
      %{}
    )
  end

  test "uses the original method after middleware mutates conn.method" do
    conn = captured_conn("body", "text/plain", original_method: "HEAD", method: "GET")

    assert {:ok, %{method: "HEAD"}} = Requests.extract_request_info(conn)
  end

  test "returns an error when the body was not captured" do
    conn = Plug.Test.conn("POST", "/bin/example", "body") |> Plug.Conn.fetch_query_params()
    assert {:error, :body_not_captured} = Requests.extract_request_info(conn)
  end

  test "request changeset accepts non-UTF-8 binary bodies" do
    changeset =
      Request.changeset(%Request{}, %{
        method: "POST",
        path: "/bin/example",
        ip: "127.0.0.1",
        bin_id: Ecto.UUID.generate(),
        body_raw: <<255, 0, 254>>
      })

    assert changeset.valid?
    assert Ecto.Changeset.get_change(changeset, :body_raw) == <<255, 0, 254>>
  end

  defp assert_info(body, content_type, expected_parsed) do
    conn = captured_conn(body, content_type)

    assert {:ok, info} = Requests.extract_request_info(conn)
    assert Map.fetch!(info, :body_raw) == body
    assert Map.fetch!(info, :body_parsed) == expected_parsed
  end

  defp captured_conn(body, content_type, opts \\ []) do
    original_method = Keyword.get(opts, :original_method, "POST")
    method = Keyword.get(opts, :method, original_method)

    method
    |> Plug.Test.conn("/bin/example?source=test", body)
    |> Plug.Conn.put_req_header("content-type", content_type)
    |> Plug.Conn.fetch_query_params()
    |> Plug.Conn.put_private(:request_bin_raw_body, body)
    |> Plug.Conn.put_private(:request_bin_original_method, original_method)
  end
end
