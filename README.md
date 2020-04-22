# yr_parser

## TL;DR
yr.no forecasts include point-in-time forecasts (for, for example, temperature), and forecasts that relate to a time range (for, for example, precipitation).

This script turns yr.no forecasts into hourly forecasts, and summaries, that are simpler to understand, and easy to script into databases and other systems.

## Usage
```
ruby yr.rb --latitude=-33.95283 --longitude=18.48056 --msl=11 --utc_offest=+2:00
```
### What you get
The script returns A JSON structure with five nodes:
Node|Description|Type
-|-|-
`changed`|Have the other nodes changed since the last time the script was run?|Boolean
`today`|Value only nodes: `precipitation`, `min_temperature`, `max_temperature`, `max_wind_speed`|Object
`three_days`|Value only nodes: `precipitation`, `min_temperature`, `max_temperature`, `max_wind_speed`|Object
`week`|Value only nodes: `precipitation`, `min_temperature`, `max_temperature`, `max_wind_speed`|Object
hourly|Object with five nodes: `from_time`, `temperatures`, `wind_speed`, `wind_direction`, `precipitation`. These nodes contain equally sized arrays which list times, temperatures etc that match the hour starting at the corresponding `from_time` entry.|Object

A detailed exploration and unit definitions can be found in "Detailed Outputs" below. Or run the script - its probably more intuitive than wading through this document!

### Parameters
`yr.rb` supports the following flags:

Short|Parameter|Detail|Required?|Type|Default
---|---|--|--|--|--
&nbsp;|--latitude|Latitude|Required|Float|
&nbsp;|--longitude|Longitude|Required|Float|
-m|--msl|Altitude|Optional|Integer|`NULL`
-b|--backoff|Minutes to pause between requests to API.|Optional|Integer|10
-u|--utc_offset|Timezone offset. For example: +2:00. It is *vital* that this offset includes a colon, as illustrated.|Optional|String|Defaults to local system.
-h|--help|Parameter definitions (this table!)|NA|NA|NA

The third parameter, *mean sea level* (I think), seems optional. Latitude, longitude and MSL are passed through to the request to the YR API.

### yr_caller.rb
To actually do something useful with the parser results, yr_caller sends each part of the resultant JSON to an AWS API Gateway endpoint - but only if the forecast has changed.
```
ruby yr.rb --latitude -33.95283 --longitude 18.48056 --msl 11 | ruby yr_caller.rb https://<your_account>.free.beeceptor.com
```
I'd expect you to change this file. In my case, the the POST is tagged with a query string parameter `source`. That server then securely relays the data to an AWS API Gateway (see [this project](https://github.com/renenw/relay)).

### With CRON
You can run this every minute. The script will not download a new forecast from YR until the current one has expired (there's no point anyway - the forecast models are only refreshed periodically). It will reflect that the forecast has changed every hour as, hourly, older forecast data is retired.
```
   *  *    *   *   *   ruby /home/pi/yr_parser/yr.rb --latitude -33.95283 --longitude 18.48056 --msl 11 | ruby /home/pi/yr_parser/yr_caller.rb http://192.168.0.252:3553/
```

## Installation
Requires a reasonably recent version of ruby. There are no other dependencies.

Clone or copy `yr.rb` and some variant of `yr_caller.rb` onto your local system. Then, setup cron jobs as appropriate.

### Logging
Logs are generated to `syslog`.

### Caching
The code will write data to a temporary file in the `/tmp` directory (and it doesn't matter if it gets deleted).

## Context
Even before Cape Town's water crisis, I got grumpy when my irrigation system watered the garden when it was raining. Or going to rain. Or watered the lawn when the wind was blowing. This lead to me building an Arduino-based, network driven switch system (the code is [here](https://github.com/renenw/harduino/blob/master/switch/switch.ino)). 

Making sure that the irrigation doesn't turn on today when its going to bucket tomorrow, obviously, requires a weather forecast. And by far the most accurate forecast for my hood is the forecast provided by the Norwegian weather service.

However, their API isn't the simplest to understand. And I missed their documentation - if it exists. Since after an interlude with DarkSky, this is the second time I'm trying to fathom their data structures, I decided to document what I did.

### Goals
Aside from documenting my learning, the script will re-purpose the forecast returned by the API to better match my requirements. It will also cache the file locally, and only refresh it based on the expiry dates provided in the meta data.

### Strategy
Specifically, the script will:
1. Download the forecast if the current forecast has expired (per the meta data in the forecast itself), or we don't have a forecast.
2. Extract forward looking forecast data.

I am only interested in:
* Temperature, rainfall and wind speed.
* Hourly forecasts and period-type summaries (today, next three days, next seven days).

## Detailed Outputs
The generated structure is as follows:
```
{
   "hourly":{
      "from_time":[
         "2020-04-22 16:00:00 UTC",
         "2020-04-22 17:00:00 UTC",
         .
         .
         .
         "2020-04-24 15:00:00 UTC"
      ],
      "temperatures":[ 17.8, 17.0, ..., 19.0 ],
      "wind_speed":[ 5.2, 5.3, 5.4, ..., 7.5 ],
      "wind_direction":[ "S", "S", "SE", ..., "S" ],
      "precipitation":[ 0.0, 0.0, 0.0, ..., 0.0 ]
   },
   "today":{
      "precipitation":0.0,
      "min_temperature":16.7,
      "max_temperature":17.8,
      "max_wind_speed":6.6
   },
   "three_days":{
      "precipitation":0.0,
      "min_temperature":14.2,
      "max_temperature":22.3,
      "max_wind_speed":8.1
   },
   "week":{
      "precipitation":0.5,
      "min_temperature":14.2,
      "max_temperature":25.1,
      "max_wind_speed":9.7
   },
   "changed":false
}
```
All entries relate only to the future (for example, you will only get the precipitation for the remainder of today in the `today` node. 

### Units
Units are as follows:
Field | Description|Unit
------|-------|----
From|Start of period|Time
To|End of period|Time
Precipitation|In may case, rainfall|mm
Temperatures|Current, minimum, maximum|&deg;C
Wind Speed|Wind speed|m/s
Wind Direction|Direction symbol|`N`, `NW` etc


## yr.no, and  API Data
You can request a forecast as follows: https://api.met.no/weatherapi/locationforecast/1.9/.json?lat=-33.95283&lon=18.48056&msl=11

This returns a JSON structure:
```
{
  created: 2020-04-15T06:58:32Z,
  product: {
    class: pointData,
    time: [232]
  }
  meta: {
     from: 2020-04-15T07:00:00Z,
     nextrun: 2020-04-15T07:31:50Z,
     runended: 2020-04-15T01:25:33Z,
     name: met_public_forecast,
     termin: 2020-04-15T01:00:00Z,
     to: 2020-04-24T06:00:00Z
  }
}
```
Our challenge is to interpret the (roughly) 232 entries in `product` | `time`.

However, to the extent that I can't compare 232 entries in my head, making sense of these 232 entries is a little tricky. The code I used to explore the data is at the end of this file.

Each entry has a start and end time, and sensibly ordered. Although, sometimes the times coincide and overlap. Or the times differ by an hour, or by six hours. Looking at the 232 entries...

### Start and End Times Match
By far the majority of the entries have the same start and end time. Of these:
* 59 entries have 14 keys: `altitude`, `cloudiness`, `dewpointTemperature`, `fog`, `highClouds`, `humidity`, `latitude`, `longitude`, `lowClouds`, `mediumClouds`, `pressure`, `temperature`, `windDirection`, `windSpeed`.
* In my case, the remainder (26 entries) are further in the future, and lack a `fog` entry.

This data seems to correspond to the data presented on the yr.no web site. Although these entries lack precipitation values. I infer that they are effectively "point in time" data. At 3pm the temperature will be 27&deg;C.

Further, the last 26 entries are detail forecasts for a six hour window. And they don't seem to overlap.

We will use this data to drive our results.

### One Hour Differential
59 entries differ by an hour, and have the following keys: `precipitation`, `symbol`, `longitude`, `latitude`, `altitude`



### Six hour differential
85 entries cover a six hour period, and have the following keys: `altitude`, `latitude`, `longitude`, `symbol`, `minTemperature`, `precipitation`, `maxTemperature`.

The time ranges overlap, and to start, increment in hours so we only actually have two weeks of predictions.

### Conclusions
We have:
* Hourly forecasts out to 48 hours, with six hourly forecasts thereafter. And these seem to be presented on the yr.no web site.
* Six hourly forecasts, out to two weeks.

As the site does, I will combine the hourly data to produce results that include temperature, wind speed, and precipitation.

### Assessment Code
Using `irb`:
```
require 'httparty'

response = HTTParty.get('https://api.met.no/weatherapi/locationforecast/1.9/.json?lat=-33.95283&lon=18.48056&msl=11')
uri  = URI('https://api.met.no/weatherapi/locationforecast/1.9/.json?lat=-33.95283&lon=18.48056&msl=11')
body = Net::HTTP.get(uri)

json = JSON.parse(body)
forecasts = json['product']['time']
```
Resultant structure includes three types of node:
1. Precipitation forecasts, containing only a precipitation element (node) with a three hour window. Three hourly, for the next three days.
1. Precipitation forecasts, containing only a precipitation element (node) with a six hour window. Three 1. hourly for the first three days, and thereafter, six hourly for the next week or so.
general forecast nodes, containing wind and all that. Six hourly, for the next week or so.

#### What do we get?
Although the forecast detail (temperature etc) will vary, the structure is broadly:
```
{
  "location"=>{
    "temperature"=>{"unit"=>"celsius", "value"=>"16.7", "id"=>"TTT"},
    "humidity"=>{"unit"=>"percent", "value"=>"72.8"},
    "altitude"=>"11",
    "latitude"=>"-33.95283",
    "fog"=>{"id"=>"FOG", "percent"=>"0.0"},
    "pressure"=>{"unit"=>"hPa", "value"=>"1024.0", "id"=>"pr"},
    "longitude"=>"18.48056",
    "lowClouds"=>{"id"=>"LOW", "percent"=>"0.8"},
    "highClouds"=>{"percent"=>"0.0", "id"=>"HIGH"},
    "dewpointTemperature"=>{"id"=>"TD", "value"=>"11.8", "unit"=>"celsius"},
    "cloudiness"=>{"id"=>"NN", "percent"=>"0.8"},
    "mediumClouds"=>{"percent"=>"0.0", "id"=>"MEDIUM"},
    "windSpeed"=>{"id"=>"ff", "beaufort"=>"1", "mps"=>"1.5", "name"=>"Flau vind"},
    "windDirection"=>{"name"=>"S", "id"=>"dd", "deg"=>"175.6"}
   },
   "from"=>"2020-04-22T07:00:00Z",
   "to"=>"2020-04-22T07:00:00Z",
   "datatype"=>"forecast"
 }
```
#### What forecast periods do our forecasts detail?
```
nodes = {}
forecasts.map { |f| [Time.parse(f['from']), Time.parse(f['to']), f] }.each { |f| h = ((f[1]-f[0])/3600).to_i; nodes[h] ||= []; nodes[h] << f[2] }

irb(main):027:0> nodes.keys
=> [0, 1, 6]

irb(main):028:0> nodes.keys.map { |k| nodes[k].count }
=> [85, 59, 85]

irb(main):029:0> Time.now
=> 2020-04-21 12:36:19.297742687 +0200

irb(main):030:0> nodes.keys.map { |k| nodes[k].map { |f| f['from'] }.max }
=> ["2020-04-30T18:00:00Z", "2020-04-23T23:00:00Z", "2020-04-30T12:00:00Z"]

```
* Zero hours: 85 nodes, through about ten days
* One hour: 59 nodes, covering about two days
* Six hours: 85 nodes, covering about ten days

#### What forecast periods do our forecasts detail?
```
irb(main):031:0> nodes[0].map { |f| f['location'].keys.count }
=> [14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 14, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13, 13]
irb(main):041:0> nodes[0].map { |f| f['location'].keys.sort }.uniq.count
=> First: ["altitude", "cloudiness", "dewpointTemperature", "fog", "highClouds", "humidity", "latitude", "longitude", "lowClouds", "mediumClouds", "pressure", "temperature", "windDirection", "windSpeed"]
=> Last:  ["altitude", "cloudiness", "dewpointTemperature",        "highClouds", "humidity", "latitude", "longitude", "lowClouds", "mediumClouds", "pressure", "temperature", "windDirection", "windSpeed"]
nodes[0].each_with_index { |f,i| p "#{i} #{Time.parse(f['from'])} #{f['location'].keys.count}  #{f['location']['temperature']['value']}" }
```
* Comparing to yr.no site data, nodes with 14 elements are hourly.
* The subsequent ones are six hourly, and lack a fog element.
```
irb(main):032:0> nodes[1].map { |f| f['location'].keys.count }
=> [5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5]
irb(main):042:0> nodes[1].map { |f| f['location'].keys.sort }.uniq.count
=> 1
=> ["precipitation", "symbol", "longitude", "latitude", "altitude"]

irb(main):033:0> nodes[6].map { |f| f['location'].keys.count }
=> [7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7]
irb(main):043:0> nodes[6].map { |f| f['location'].keys.sort }.uniq.count
=> 1
==> ["altitude", "latitude", "longitude", "symbol", "minTemperature", "precipitation", "maxTemperature"]
```
#### A Caveat
The  correspondence between the 59 point-in-time nodes, and the 59 nodes precipitation nodes is not always perfect:
```
irb(main):036:0> zero = nodes[0].select { |e| e['location'].keys.count==14 }.map { |e| e['from'] }
irb(main):037:0> one = nodes[1].map { |e| e['from'] }
irb(main):038:0> one - zero
=> ["2020-04-21T10:00:00Z"]
irb(main):039:0> zero - one
=> ["2020-04-24T00:00:00Z"]
irb(main):040:0> one.last
=> "2020-04-23T23:00:00Z"
irb(main):041:0> zero.last
=> "2020-04-24T00:00:00Z"
irb(main):042:0> one.first
=> "2020-04-21T10:00:00Z"
irb(main):043:0> zero.first
=> "2020-04-21T11:00:00Z"
```

