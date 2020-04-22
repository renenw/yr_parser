require 'optparse'
require 'json'
require 'time'
require 'uri'
require "net/http"
require 'syslog/logger'
require 'digest/sha1'

# ruby yr.rb --latitude -33.95283 --longitude 18.48056 --msl 11

# ELEMENTS = %w(dewpointTemperature fog highClouds humidity lowClouds mediumClouds pressure temperature windDirection windSpeed precipitation symbol minTemperature maxTemperature).map(&:to_sym)
ELEMENTS = %w(temperature windDirection windSpeed precipitation symbol minTemperature maxTemperature).map(&:to_sym)

@latitude   = nil
@longitude  = nil
@msl        = 0
@utc_offest = nil
@backoff    = 10

@log = Syslog::Logger.new 'YR_PARSER'

def log(line)
	@log.info(line)
end

# {
# 	expires: <time>,
# 	last_updated: <time>,
# 	yr_forecast: <json>,
# }


def filename
	'/tmp/' + "yr_parser_#{@latitude}_#{@longitude}_#{@msl}".gsub(/\W/,'_')
end

def clean(json)
	json[:last_processed_at] = Time.parse(json[:last_processed_at])  if json[:last_processed_at] && json[:last_processed_at].is_a?(String)
	json[:last_requested_at] = Time.parse(json[:last_requested_at])  if json[:last_requested_at] && json[:last_requested_at].is_a?(String)
	json[:last_requested_at] = @now - 100*60*60      								 if json[:last_requested_at].nil?
	json
end


def read_cached_data
	json = nil
	if File.file?(filename)
		json = JSON.parse(File.read(filename), symbolize_names: true)
	else
		log('Cache file not found.')
	end
	json
end

def save_cache(json)
	File.write(filename, json.to_json)
end

def get_forecast_from_yr
	url  = "https://api.met.no/weatherapi/locationforecast/1.9/.json?lat=#{@latitude}&lon=#{@longitude}&msl=#{@msl}"
	log("Will request #{url}")
	uri  = URI(url)
	body = Net::HTTP.get(uri)
	JSON.parse(body, symbolize_names: true)
end

def get_new_forecast?(data)
	fetch = true
	if !data[:yr_forecast].nil?
		next_run_date = data[:yr_forecast][:meta][:model][:nextrun]                 rescue nil
		next_run_date = Time.parse(next_run_date)                                   if next_run_date
		log('Next run date unavailable. Will request new forecast from YR.')        if next_run_date.nil?
		log('Next run date has passed. Will request new forecast from YR.')         if !next_run_date.nil? && (next_run_date < @now)
		log('New forecast probably not available. Do not fetch.')                   if !next_run_date.nil? && (next_run_date > @now)
		fetch         = next_run_date.nil? || (next_run_date < @now)
		log('In backoff window. Will not request new forecase.')                    if fetch && !(data[:last_requested_at] < (@now - 60*@backoff))
		fetch         = fetch && data[:last_requested_at] < (@now - 60*@backoff)
	end
	fetch
end

def get_data
	data = read_cached_data || {}
	data = clean(data)                                                                     if data
	if get_new_forecast?(data)
		data[:last_requested_at] = @now
		data[:yr_forecast]       = get_forecast_from_yr
	end
	data = clean(data)                                                                     if data
	data = { latitude: @latitude, longitude: @longitude, msl: @msl, utc_offset: @offset }  if data==nil
	data
end


def parse(source_data)

	result    = { hourly: {}, today: {}, three_days: {}, week: {} }

	key_count = nil
	data = source_data[:yr_forecast][:product][:time].map do |f|

		r = {
			from: f[:from],
			to:   f[:to],
			type: :point,
		}

		ELEMENTS.each do |e|
			node = f[:location][e]
			if node
				r[e] = case e
									when :precipitation  then node[:value].to_f
									when :temperature    then node[:value].to_f
									when :windSpeed      then node[:mps].to_f
									when :windDirection  then node[:name]
									when :symbol         then node[:id]
									when :minTemperature then node[:value].to_f
  								when :maxTemperature then node[:value].to_f
									else node
									end
			end
		end

		r[:from] = Time.parse(r[:from])  if r[:from].is_a?(String)
		r[:to]   = Time.parse(r[:to])    if r[:to].is_a?(String)

		r[:type] = :hourly  if (r[:from] +   60*60)==r[:to]
		r[:type] = :six     if (r[:from] + 6*60*60)==r[:to]

		if r[:type]==:point
			key_count = key_count || f[:location].keys.count
			r[:to]    = r[:to] + ( f[:location].keys.count==key_count ? 60*60 : 6*60*60 )
		end

		r[:id]   = "#{r[:from].to_i}:#{r[:to].to_i}"

		r

	end.select { |f| f[:from]>@now }

	point_forecasts      = data.select { |f| f[:type]==:point }
	hourly_forecasts     = data.select { |f| f[:type]==:hourly }
	six_hourly_forecasts = data.select { |f| f[:type]==:six }

	# add precipitation data to hourly forecasts (note that after a while the hourly forecasts become six hourly)
	rain_hourly          = hourly_forecasts.map     { |f| [f[:id], f[:precipitation]] }.to_h
	rain_six             = six_hourly_forecasts.map { |f| [f[:id], f] }.to_h
	point_forecasts      = point_forecasts.each do |f|
		f[:precipitation]  = rain_hourly[f[:id]] || (rain_six[f[:id]] || {})[:precipitation] || 0
		sky                = (rain_six[f[:id]] || {})[:symbol]
		f[:sky]            = sky  if sky
	end

	# hourly
	hourly                           = point_forecasts.first(48)
	result[:hourly][:from_time]      = hourly.map { |f| f[:from] }
	result[:hourly][:temperatures]   = hourly.map { |f| f[:temperature] }
	result[:hourly][:wind_speed]     = hourly.map { |f| f[:windSpeed] }
	result[:hourly][:wind_direction] = hourly.map { |f| f[:windDirection] }
	result[:hourly][:precipitation]  = hourly.map { |f| f[:precipitation] }

	# day_view
	hourly = point_forecasts.select { |h| h[:to]<=(@start_of_day+24*60*60) }
	result[:today][:precipitation]   = hourly.map { |f| f[:precipitation] }.compact.sum
	result[:today][:min_temperature] = hourly.map { |f| f[:temperature]   }.compact.min
	result[:today][:max_temperature] = hourly.map { |f| f[:temperature]   }.compact.max
	result[:today][:max_wind_speed]  = hourly.map { |f| f[:windSpeed]     }.compact.max

	# we need to get the hourly data for the period through to when our six hourly data starts
	hourly = point_forecasts.select { |h| h[:to]<= six_hourly_forecasts.map { |f| f[:from] }.min } 
	precipitation     = hourly.map { |f| f[:precipitation] }.compact.sum
	min_temperature   = hourly.map { |f| f[:temperature]   }.compact.min
	max_temperature   = hourly.map { |f| f[:temperature]   }.compact.max
	wind_speed        = hourly.map { |f| f[:windSpeed]     }.compact.max

  # three day view
	forecasts = point_forecasts.select { |h| h[:from] < (@start_of_day+3*24*60*60) }
	result[:three_days][:precipitation]   = forecasts.map  { |f| f[:precipitation] }.compact.sum + precipitation
	result[:three_days][:min_temperature] = [forecasts.map { |f| f[:temperature]   }.compact.min, min_temperature].compact.min
	result[:three_days][:max_temperature] = [forecasts.map { |f| f[:temperature]   }.compact.max, max_temperature].compact.max
	result[:three_days][:max_wind_speed]  = [forecasts.map { |f| f[:windSpeed]     }.compact.max, wind_speed].compact.max
	
	# week view
	forecasts = point_forecasts.select { |h| h[:from] < (@start_of_day+7*24*60*60) }
	result[:week][:precipitation]   = forecasts.map  { |f| f[:precipitation] }.compact.sum + precipitation
	result[:week][:min_temperature] = [forecasts.map { |f| f[:temperature]   }.compact.min, min_temperature].compact.min
	result[:week][:max_temperature] = [forecasts.map { |f| f[:temperature]   }.compact.max, max_temperature].compact.max
	result[:week][:max_wind_speed]  = [forecasts.map { |f| f[:windSpeed]     }.compact.max, wind_speed].compact.max

	result

end

def process
	data                     = get_data
	forecast                 = parse(data)
	data[:last_processed_at] = @now
	sha1                     = Digest::SHA1.hexdigest(forecast.to_json)
	forecast[:changed]       = (sha1!=data[:sha1])
	data[:sha1]              = sha1
	save_cache(data)
	forecast
end


def set_parameters

	parser = OptionParser.new do|opts|
		opts.banner = "Usage: ruby yr.rb --latitude=-33.95283 --longitude=18.48056 --msl=11 --utc_offest=+200"
		opts.on('--latitude latitude', Float, 'Latitude is required. Float.') do |l|
			@latitude = l
		end
		opts.on('--longitude longitude', Float, 'Longitude is required. Float.') do |l|
			@longitude = l
		end
		opts.on('-msl', '--msl msl', Integer, 'MSL is optional. Integer.') do |msl|
			@msl = msl
		end
		opts.on('-b' '--backoff backoff', Integer, 'Minutes to pause between requests to API. Integer.') do |backoff|
			@backoff = backoff
		end
		opts.on('-u' '--utc_offset offset', String, 'Timezone offset. For example: +200. Defaults to local system.') do |offset|
			@utc_offset = offset
		end
		opts.on('-h', '--help', 'Help') do
			puts opts
			exit
		end
	end

	parser.parse!

	raise OptionParser::MissingArgument('Latitude')  unless @latitude
	raise OptionParser::MissingArgument('Longitude') unless @longitude

	@utc_offset   = @utc_offset || Time.now.strftime('%:z')
	@now          = Time.now
	@now          = Time.now.localtime(@utc_offset)  if @utc_offset
	@start_of_day = Time.local(@now.year, @now.month, @now.day)

	log("Will run for #{@latitude}; #{@longitude} #{@msl || 0}m. UTC offset: #{@utc_offset || 'UTC'}. Backoff time: #{@backoff} minutes")
	log("Cache file: #{filename}")

end

parameters = false
begin
	set_parameters
	parameters = true
rescue
	puts 'Unable to parse parameters. --help for details.'
end

puts process.to_json  if parameters
