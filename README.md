Bucky
=====

Bucky is a client and server for sending performance data from the client into statsd+graphite, OpenTSDB, InfluxDB, or any
other stats aggregator of your choice.

Bucky can measure how long your pages take to load, how long AJAX requests take, and how long
various functions take to run.  Most importantly, it's taking the measurements on actual page loads,
so the data has the potential to be much more valuable than in vitro measurements.

If you already use statsd, OpenTSDB or InfluxDB, you can get started in just a few minutes.  If you're not
collecting stats, you [should start](http://github.hubspot.com/BuckyServer/getting_started/choosing_a_stats_service/)!
What gets measured gets managed.

### Server

You can play with Bucky just using the client, but if you'd like to start collecting data, see the
[Server Instructions](http://github.hubspot.com/BuckyServer/).

### Setup

#### From The Client

Include [bucky.js](https://raw.github.com/HubSpot/BuckyClient/v0.3.0/bucky.min.js) on your page. All of the required configuration can be done right in the script tag:

```html
<script src="bucky.js" data-bucky-host="/bucky" data-bucky-page data-bucky-requests></script>
```

The example above sets up Bucky to report on page load performance and all XMLHttpRequests. The [data-bucky-host] attribute configures Bucky to send the reporting data to a server that's listening at /bucky.  Since no key string was listed Bucky will automatically generate a key name based on the url of the page.  If you'd like, you can also specify it manually:

```html
<script src="bucky.js" data-bucky-host="/bucky" data-bucky-page="index" data-bucky-requests="index"></script>
```

Here are the full list of options available as attributes with example values:
- `data-bucky-host="/bucky"`: Where we can reach your [Bucky server](http://github.com/HubSpot/BuckyServer), including the
  APP_ROOT.

  The Bucky server has a very liberal CORS config, so we should be able to connect to it even if
  it's on a different domain, but hosting it on the same domain and port will save you some preflight requests.

- `data-bucky-page="page"`: Turns on page performance logging, this example assigns the key "page".

- `data-bucky-requests="xhr"`: Turns on XMLHttpRequest monitoring, this example assigns the key "xhr".

- `data-bucky-json="true"`: Setting this flag to true changes the output to json. By default Bucky outputs using a line format similar to what's used by statsd.

- `data-bucky-influx-line-protocol="true"`: Change the output to use InfluxDB Line Protocol. The data-bucky-json attribute must setting must be set to true for this option.

- `data-bucky-query-string="escape|replace"`: This option only applies to InfluxDB Line Protocol. The two accepted values for this attribute are "escape" and "replace". When InfluxDB Line protocol is used the full URL will be attached as a tag. If the URL contains a query string, due to InfluxDB Line Protocol restrictions, either the = in the query string will need to be escaped to make the query string part of the URL, or the ? and & need to be replaced with commas to create additional tags.


This will create a `Bucky` object with the set attributes. This object will be available globally but there is nothing you need to call for basic usage.

Bucky can also be loaded with AMD or Browserify (see the methods below).

#### From Node

```bash
npm install bucky
```

```coffeescript
Bucky = require 'bucky'
```

### Configuring

Before sending any data you can call the `setOptions` to set any configuration options. Be aware that configuration set using `setOptions` will override any data attributes that were set in the script tag.

```javascript
Bucky.setOptions({
  host: 'http://my.web.hostname:5999/bucky'
});
```

Some options you might be interested in:

- `host`: Where we can reach your [Bucky server](http://github.com/HubSpot/BuckyServer), including the
  APP_ROOT.

  The Bucky server has a very liberal CORS config, so we should be able to connect to it even if
  it's on a different domain, but hosting it on the same domain and port will save you some preflight requests.

- `active`: Should Bucky actually send data?  Use this to disable Bucky during local dev for example.
- `sample`: What fraction of clients should actually send data?  Use to subsample your clients if you have
  too much data coming in.
- `json`: Boolean flag for sending data to the server as json instead of statsd line protocol. Default is false (to use statsd line protocol).
- `influxLineProtocol`: Boolean flag to change the format of the output to optimize for InfluxDB Line Protocol. Default is False. (influxLineProtocol requires the json flag to be set to true).
- `queryString`: This option only applies to InfluxDB Line Protocol. The two accepted values are "escape" and "replace". When InfluxDB Line protocol is used the full URL will be attached as a tag. If the URL contains a query string, due to InfluxDB Line Protocol restrictions, either the = in the query string will need to be escaped to make the query string part of the URL, or the ? and & need to be replaced with commas to create additional tags. The default is null.
Take a look at [the source](http://github.com/HubSpot/BuckyClient/blob/master/bucky.coffee#L34) for a
full list of options.

#### Sending Page Performance

Modern browsers log a bunch of page performance data, bucky includes a method for writing all of this in
one go.  It won't do anything on browsers which don't support the performance.timing api.  Call it whenever,
it will bind an event if the data isn't ready yet.

```coffeescript
Bucky.sendPagePerformance 'key.for.the.data'
```

This function gets called by default if the `data-bucky-page` attribute is set in the script tag.

The two most relevant stats provided are `responseEnd` which is the amount of time it took for the
original page to be loaded and `domInteractive` which is the amount of time before the page has
finished loaded and can be interacted with by the user.

As a reminder: this data is browser specific, so it will likely skew lower than what users on
old browsers see.

If you're using Backbone, it might be a good idea to send your data based on route:

```coffeescript
Backbone.history.on 'route', (router, route) ->
   # Will only send on the initial page load:
   Bucky.sendPagePerformance "key.page.#{ route }"
```

This is how the data will be sent to the server after page has fully loaded:

With the default statsd line protocol style syntax:

```text
key.page.routeName.connectEnd:172.000|ms
key.page.routeName.connectStart:106.000|ms
key.page.routeName.domComplete:1029.000|ms
key.page.routeName.domContentLoadedEventEnd:1019.000|ms
key.page.routeName.domContentLoadedEventStart:980.000|ms
key.page.routeName.domInteractive:980.000|ms
```

With JSON turned on:

```javascript
{
  "key.page.routeName.domLoading": "254.000|ms",
  "key.page.routeName.domainLookupEnd": "106.000|ms",
  "key.page.routeName.domainLookupStart": "106.000|ms",
  "key.page.routeName.fetchStart": "103.000|ms",
  "key.page.routeName.loadEventEnd": "1030.000|ms",
  "key.page.routeName.loadEventStart": "1029.000|ms"
}
```

And with JSON and Influx Line Protocol:

```javascript
{
  "key.page.routeName,url=http://window.location.string,timing=navigationStart": "0.000|ms",
  "key.page.routeName,url=http://window.location.string,timing=requestStart": "173.000|ms",
  "key.page.routeName,url=http://window.location.string,timing=responseEnd": "243.000|ms",
  "key.page.routeName,url=http://window.location.string,timing=responseStart": "235.000|ms",
  "key.page.routeName,url=http://window.location.string,timing=secureConnectionStart": "106.000|ms"
}
```

A description of what each datapoint represents is included in [the spec](http://www.w3.org/TR/navigation-timing-2/#sec-PerformanceNavigationTiming).

#### Sending AJAX Request Time

Bucky can automatically log all ajax requests made by hooking into XMLHttpRequest and doing some transformations
on the url to try and create a graphite key from it.  Enable it as early in your app's load as is possible:

```coffeescript
Bucky.requests.monitor 'my.project.requests'
```

This function gets called by default if the `data-bucky-requests` attribute is set in the script tag.

This is how the data will be sent to the server for a GET request to
`api.hubapi.com/automation/v2/workflows`:

With the default statsd line protocol style syntax:

```text
my.project.requests.api.hubapi.automation.v2.workflows.get:656.794|ms
my.project.requests.api.hubapi.automation.v2.workflows.get.2xx:1|c
my.project.requests.api.hubapi.automation.v2.workflows.get.200:1|c
```

With JSON turned on:

```javascript
{
  "my.project.requests.api.hubapi.automation.v2.workflows.get.headers": "436.737|ms",
  "my.project.requests.api.hubapi.automation.v2.workflows.get.receiving": "0.182|ms"
}
```

And with JSON and Influx Line Protocol:

```javascript
{
  "my.project.requests,url=http://window.location,endpoint=http://api.hubapi.com/automation/v2/workflows,method=get,status=sending": "0.059|ms",
  "my.project.requests,url=http://window.location,endpoint=http://api.hubapi.com/automation/v2/workflows,method=get,status=waiting": "206.035|ms"
}
```

#### Prefixing

You can build a client which will prefix all of your datapoints by calling bucky as a function:

```coffeescript
myBucky = Bucky 'awesome.app.view'

# You can then use all of the normal methods:
myBucky.send 'data.point', 5
```

You can repeatedly call clients to add more prefixes:

```coffeescript
contactsBucky = bucky 'contacts'
cwBucky = contactsBucky 'web'

cwBucky.send('x', 1) # Data goes in contacts.web.x
```

#### Counting Things

By default `send` sends absolute values, this is rarely what you want when working from the client, incrementing
a counter is usually more helpful:

```coffeescript
bucky.count 'my.awesome.thing'
bucky.count 'number.of.chips.eaten', 5
```

#### Timing Things

You can manually send ms durations using `timer.send`:

```coffeescript
bucky.timer.send 'timed.thing', 55
```

Bucky includes a method to time async functions:

```coffeescript
bucky.timer.time 'my.awesome.function', (done) ->
  asyncThingy ->
    done()
```

You can also manually start and stop your timer:

```coffeescript
bucky.timer.start 'my.awesome.function'

asyncThingy ->
  bucky.timer.stop 'my.awesome.function'
```

You can time synchronous functions as well:

```coffeescript
bucky.timer.timeSync 'my.awesome.function', ->
  Math.sqrt 100
```

The `time` and `timeSync` functions also accept a context and arguments to pass to the
called function:

```coffeescript
bucky.timer.timeSync 'my.render.function', @render, @, arg1, arg2
```

You can wrap existing functions using `wrap`:

```coffeescript
func = bucky.timer.wrap 'func.time', func
```

It also supports a special syntax for methods:

```coffeescript
class SomeClass
  render: bucky.timer.wrap('render') ->
    # Normal render stuff
```

Note that this wrapping does not play nice with CoffeeScript `super` calls.

Bucky also includes a function for measuring the time since the navigationStart event was fired (the beginning of the request):

```coffeescript
bucky.timer.mark 'my.thing.happened'
```

It acts like a timer where the start is always navigation start.

The stopwatch method allows you to begin a timer which can be stopped multiple times:

```coffeescript
watch = bucky.stopwatch 'some.prefix.if.you.want'
```

You can then call `watch.mark('key')` to send the time since the stopwatch started, or
`watch.split('key')` to send the time since the last split.

### Sending Points

If you want to send absolute values (rare from the client), you can use send directly.

The one use we've had for this is sending `+new Date` from every client to get an idea
of how skewed their clocks are.

```coffeescript
Bucky.send 'my.awesome.datapoint', 2432.43434
```

### Your Stats

You can find your stats in the `stats` and `stats.timing` folders in graphite, or as written in OpenTSDB.

### Send Frequency

Bucky will send your data in bulk from the client either five seconds after the last datapoint is added, or thirty seconds after
the last send, whichever comes first.  If you log multiple datapoints within this send frequency, the points will
be averaged (and the appropriate frequency information will be sent to statsd) (with the exception of counters, they
are incremented).  This means that the max and min numbers you get from statsd actually represent the max and min
5-30 second bucket.  Note that this is per-client, not for the entire bucky process (it's generally only important
on the server where you might be pushing out many points with the same key).

### Bucky Object

The Bucky object provides a couple extra properties you can access:

- `Bucky.history`: The history of all datapoints ever sent.
- `Bucky.active`: Is Bucky sending data?  This can change if you change the `active` or `sample` settings.
- `Bucky.flush()`: Send the Bucky queue immediately
- `Bucky.timer.now()`: A clock based on the most precise time available (not guarenteed to be from the epoch)

### URL -> Key Transformation

`request.monitor` attempts to automatically transform your urls into keys.  It does a bunch of transformations
with the goal of removing anything which will vary per-request, so you end up with stats per-endpoint.  These
tranformations include:

- Stripping GUIDS, IDs, SHA1s, MD5s
- Stripping email addresses
- Stripping domains

If you find these tranformations too invasive, or not invasive enough, you can modify them.

```javascript
// You can diable tranforms with `.disable`
Bucky.requests.transforms.disable('guid');

// You can enable transforms with `.enable`
Bucky.requests.tranforms.enable('guid');

// `.enable` can also be used to add a new tranform:
Bucky.requests.transforms.enable('my-ids', /[0-9]{4}-[0-9]{12}/g)

// The third argument defines what the match is replaced with (rather than just eliminating it):
Bucky.requests.transforms.enable('campaign', /campaigns\/\w{15}/ig, '/campaigns')

// You can also just provide a function which takes in the url, and returns it modified:
Bucky.request.transforms.enable('soup', function(url){ return url.split('').reverse().join(''); })
```

Enabled tests will be added to the beginning of the `enabled` list, meaning they will be executed before
any other tranform.  Edit the `Bucky.requests.tranforms.enabled` array if you need more specific control.

The order of the transforms is very important.  If you, for example, were to run the `id` transform before
the `guid` one, the `guid` transform wouldn't match any guid which began with a number (as the number would
have already been stripped out, making the guid the wrong length).

When you first enable request monitoring, it's a good idea to keep an eye on the Bucky logs to get
an idea of what sort of data points are being created.

### App Server

This project pushes data to the Bucky Server.

[Server Documentation](http://github.hubspot.com/BuckyServer)

<script src="http://github.hubspot.com/BuckyClient/bucky.js"></script>
