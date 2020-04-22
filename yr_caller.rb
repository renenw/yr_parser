require 'json'
require 'syslog/logger'
require 'net/http'
require 'net/https'
require 'uri'

@log = Syslog::Logger.new 'YR_CALLER'

def log(line)
	@log.info(line)
end

def post(name, detail)

	uri          = URI.parse("#{@url}?source=weather_#{name}")
	http         = Net::HTTP.new(uri.host, uri.port)
	http.use_ssl = true  if @url=~/https/i
	request      = Net::HTTP::Post.new(uri.request_uri, 'Content-Type' => 'application/json')
	request.body = detail.to_json

	response = http.request(request)

	log('Error uploading data') if !response.code.start_with?('2')

end


def process
	json = JSON.parse(@input, symbolize_names: true)
	if json[:changed] || true
		log("Will uppload to #{ARGV[0]}")
		%w(hourly today three_days week).map(&:to_sym).each do |key|
			post(key, json[key])
		end
	else
		log('No change.')
	end

end

if ARGV[0] && ARGV[0].start_with?('http')
	@url   = ARGV[0]
	@input = STDIN.gets
	process
else
	p 'Please provide a target url to post to'
end
