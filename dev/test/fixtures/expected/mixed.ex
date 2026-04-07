defmodule Example.Mixed do
  @default_timeout 5000
  @max_retries     3
  @base_url        "https://api.example.com"
  @version         "v1"

  def build_request(method, path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    retries = Keyword.get(opts, :retries, @max_retries)
    headers = Keyword.get(opts, :headers, [])
    body    = Keyword.get(opts, :body,    nil)

    %{
      method:  method,
      url:     "#{@base_url}/#{@version}/#{path}",
      timeout: timeout,
      retries: retries,
      headers: headers,
      body:    body
    }
  end

  def dispatch(request) do
    case request.method do
      :get    ->
        HTTPClient.get(request.url, request.headers, timeout: request.timeout)
      :post   ->
        HTTPClient.post(request.url, request.body, request.headers, timeout: request.timeout)
      :put    ->
        HTTPClient.put(request.url, request.body, request.headers, timeout: request.timeout)
      :delete ->
        HTTPClient.delete(request.url, request.headers, timeout: request.timeout)
    end
  end
end