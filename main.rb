require 'rubygems'
require 'sinatra'
require 'net/http'
require 'json'
require 'uri'

configure do
  Rack::Mime::MIME_TYPES['.manifest'] = 'text/cache-manifest'
end

get '/' do
  redirect '/index.html'
end

# Proxy endpoint for Claude API to avoid CORS issues
post '/api/split-task' do
  content_type :json

  begin
    # Get request data
    request.body.rewind
    data = JSON.parse(request.body.read)

    api_key = data['api_key']
    task_text = data['task']

    # Validate inputs
    if api_key.nil? || api_key.empty?
      status 400
      return { error: 'API key is required' }.to_json
    end

    if task_text.nil? || task_text.empty?
      status 400
      return { error: 'Task text is required' }.to_json
    end

    # Prepare request to Anthropic API
    uri = URI('https://api.anthropic.com/v1/messages')
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.read_timeout = 30

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request['x-api-key'] = api_key
    request['anthropic-version'] = '2023-06-01'

    request.body = {
      model: 'claude-3-5-sonnet-20241022',
      max_tokens: 1024,
      messages: [{
        role: 'user',
        content: "Break down this task into 3-5 concrete, actionable subtasks. Return only the subtasks, one per line, without numbering or bullets:\n\n#{task_text}"
      }]
    }.to_json

    # Make the request
    response = http.request(request)

    # Return the response
    status response.code.to_i
    response.body

  rescue JSON::ParserError => e
    status 400
    { error: 'Invalid JSON in request body' }.to_json
  rescue Net::ReadTimeout => e
    status 504
    { error: 'Request to Claude API timed out' }.to_json
  rescue StandardError => e
    status 500
    { error: "Server error: #{e.message}" }.to_json
  end
end
