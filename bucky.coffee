if process?.hrtime?
  # On the server
  now = ->
    time = process.hrtime()
    (time[0] + time[1] / 1e9) * 1000

else
  # On the client
  now = ->
    window.performance?.now?() ? (+new Date)

# This is used if we can't get the navigationStart time from
# window.performance
initTime = +new Date

exportDef = (Env, _, $, Frosting) ->
  # The max time we should wait between sends
  MAX_INTERVAL = 30000

  # How long we should wait from getting the last datapoint
  # to do a send, if datapoints keep coming in eventually
  # the MAX_INTERVAL will trigger a send.
  AGGREGATION_INTERVAL = 5000

  DECIMAL_PRECISION = 3

  # Bucky can automatically report a datapoint of what it's response time
  # is.  This is useful because Bucky returns almost immediately, making
  # it's response time a good measure of the user's connection latency.
  SEND_LATENCY = true

  # Downsampling will cause Bucky to only send data 100*SAMPLE percent
  # of the time.  It is used to reduce the amount of data sent to the backend.  Keep
  # in mind that the goal is to have each datapoint sent at least once per minute.
  #
  # It's not done per datapoint, but per client, so you probably don't want to downsample
  # on node (you would be telling a percentage of your servers to not send data).
  SAMPLE = 1

  TYPE_MAP =
    'timer': 'ms'
    'gauge': 'g'
    'counter': 'c'

  HOSTS =
    'prod': 'https://app.hubspot.com/bucky'
    'qa': 'https://app.hubspotqa.com/bucky'

  BUCKY_HOST = HOSTS[Env.getInternal('api.bucky')] ? HOSTS.qa

  ACTIVE = Math.random() < SAMPLE

  # Should we console.log if an ajax request is ended without us having recorded
  # the start time (usually means requests.monitor is being called too late).
  WARN_UNSTARTED_REQUEST = true

  HISTORY = {}

  round = (num, precision=DECIMAL_PRECISION) ->
    num.toFixed(precision)

  queue = {}
  enqueue = (path, value, type) ->
    return unless ACTIVE

    count = 1

    if path of queue
      # We have multiple of the same datapoint in this queue
      if type is 'counter'
        # Sum the queue
        value += queue[path].value
      else
        # If it's a timer or a gauge, calculate a running average
        count = queue[path].count ? count
        count++

        value = queue[path].value + (value - queue[path].value) / count

    HISTORY[path] = queue[path] = {value, type, count}

    do considerSending

  sendTimeout = null
  maxTimeout = null

  flush = ->
    clearTimeout sendTimeout
    clearTimeout maxTimeout

    maxTimeout = null
    sendTimeout = null

    do sendQueue

  considerSending = ->
    # We set two different timers, one which resets with every request
    # to try to get as many datapoints into each send, and another which
    # will force a send if too much time has gone by with continuous
    # points coming in.

    clearTimeout sendTimeout
    sendTimeout = setTimeout flush, AGGREGATION_INTERVAL

    unless maxTimeout?
      maxTimeout = setTimeout flush, MAX_INTERVAL

  sendQueue = ->
    unless Env.deployed?('bucky')
      #console.log "Would send bucky queue"
      return

    out = {}
    for key, point of queue
      unless TYPE_MAP[point.type]?
        console.error "Type #{ point.type } not understood by Bucky"
        continue

      if point.type is 'timer' and point.value > 120000
        # Throw out impossible times
        continue

      value = point.value
      if point.type in ['gauge', 'timer']
        value = round(value)

      out[key] = "#{ value }|#{ TYPE_MAP[point.type] }"

      if point.count isnt 1
        out[key] += "@#{ round(1 / point.count, 5) }"

    sendStart = now()
    $.ajax
      url: BUCKY_HOST + '/send'
      type: 'POST'
      contentType: 'application/json'
      data: JSON.stringify out
      _buckySend: true
      error: (e) ->
        console.error e, "sending data"
      success: ->
        sendEnd = now()

        updateLatency(sendEnd - sendStart)

    queue = {}

  getHistory: ->
    HISTORY

  currentLatency = 0
  latencySent = false
  updateLatency = (time) ->
    currentLatency = time

    if SEND_LATENCY and not latencySent
      enqueue 'bucky.latency', time, 'timer'

      latencySent = true

      # We may be running on node where this process could be around for
      # a while, let's send latency updates every five minutes.
      setTimeout ->
        latencySent = false
      , 5*60*1000

  makeClient = (prefix='') ->
    buildPath = (path) ->
      if prefix?.length
        path = prefix + '.' + path

      path.replace '.ENV.', ".#{ Env.getInternal('bucky') }."

    send = (path, value, type='gauge') ->
      enqueue buildPath(path), value, type

    timer = {
      TIMES: {}

      send: (path, duration) ->
        send path, duration, 'timer'

      time: (path, action, ctx, args...) ->
        timer.start path

        done = =>
          timer.stop path

        args.splice(0, 0, done)
        action.apply(ctx, args)

      timeSync: (path, action, ctx, args...) ->
        timer.start path

        ret = action.apply(ctx, args)

        timer.stop path

        ret

      wrap: (path, action) ->
        if action?
          return (args...) ->
            timer.timeSync path, action, @, args...
        else
          return (action) ->
            return (args...) ->
              timer.timeSync path, action, @, args...

      start: (path) ->
        timer.TIMES[path] = now()

      stop: (path) ->
        if not timer.TIMES[path]?
          console.error "Timer #{ path } ended without having been started"
          return

        duration = now() - timer.TIMES[path]

        timer.TIMES[path] = undefined

        timer.send path, duration

      stopwatch: (prefix, start) ->
        # A timer that can be stopped multiple times

        # If a start time is passed in, it's assumed
        # to be millis since the epoch, not the special
        # start time `now` uses.
        if start?
          _now = -> +new Date
        else
          start = now()
          _now = now

        last = start

        {
          mark: (path, offset=0) ->
            end = _now()

            if prefix
              path = prefix + '.' + path

            timer.send path, (end - start + offset)

          split: (path, offset=0) ->
            end = _now()

            if prefix
              path = prefix + '.' + path

            timer.send path, (end - last + offset)

            last = end
        }

      mark: (path, time) ->
        # A timer which always begins at page load

        time ?= +new Date

        start = timer.navigationStart()

        timer.send path, (time - start)

      navigationStart: ->
        window?.performance?.timing?.navigationStart ? initTime

      responseEnd: ->
        window?.performance?.timing?.responseEnd ? initTime

      now: ->
        now()
    }

    count = (path, count=1) ->
      send(path, count, 'counter')

    sentPerformanceData = false
    sendPerformanceData = (path='timing') ->
      return false unless window?.performance?.timing?
      return false if sentPerformanceData

      if document.readyState in ['uninitialized', 'loading']
        # The data isn't fully ready until document load
        document.addEventListener? 'DOMContentLoaded', ->
          sendPerformanceData.apply(@, arguments)

        return

      sentPerformanceData = true

      start = window.performance.timing.navigationStart
      for key, time of window.performance.timing
        if time isnt 0
          send "#{ path }.#{ key }", (time - start), 'timer'

      return true

    requests = {
      sendReadyStateTimes: (path, times) ->
        return unless times?

        codeMapping =
          1: 'sending'
          2: 'headers'
          3: 'waiting'
          4: 'receiving'

        diffs = {}
        last = null
        for code, time of times
          if last? and codeMapping[code]?
            diffs[codeMapping[code]] = time - last

          last = time

        for status, val of diffs
          send "#{ path }.#{ status }", val, 'timer'

      urlToKey: (url, type, root) ->
        url = url.replace /https?:\/\//i, ''

        parsedUrl = /([^/:]*)(?::\d+)?(\/[^\?#]*)?.*/i.exec(url)
        host = parsedUrl[1]
        path = parsedUrl[2] ? ''

        path = path.replace(/\/events?\/\w{8,12}/ig, '/events') # Analytics events
        path = path.replace(/\/campaigns?\/\w{15}(\w{3})?/ig, '/campaigns') # SF campaigns
        path = path.replace(/\/_[^/]+/g, '') # Contact secure ids
        path = path.replace(/\.js$/, '') # JS file extensions
        path = path.replace(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig, '') # GUIDs
        path = path.replace(/\/[0-9a-f]{40}/ig, '') # Sha1s
        path = path.replace(/\/[0-9a-f]{32}/ig, '') # MD5s
        path = path.replace(/\/[0-9;_\-]+/g, '') # Ids, including content's ; seperated ones, import ids, and social underscore-joined ids
        path = path.replace(/\/[^/]+@[^/]+/g, '') # Email addresses
        path = path.replace(/\/[^/]+\.[a-z]{2,3}/ig, '') # Domains in the URL
        path = path.replace(/\/static(\-\d+\.\d+)?/g, '/static') # Static version identifiers

        path = decodeURIComponent(path)

        path = path.replace(/[^a-zA-Z0-9\-\.\/ ]+/g, '_')

        stat = host + path.replace(/[\/ ]/g, '.')

        stat = stat.replace /(^\.)|(\.$)/g, ''
        stat = stat.replace /\.com/, ''
        stat = stat.replace /www\./, ''

        if root
          stat = root + '.' + stat

        if type
          stat = stat + '.' + type.toLowerCase()

        stat = stat.replace /\.\./g, '.'

        stat

      getFullUrl: (url, location=document.location) ->
        if /^\//.test(url)
          location.hostname + url
        else if not /https?:\/\//i.test(url)
          location.toString() + url
        else
          url

      monitor: (root='requests') ->
        lastXHR = undefined
        jQuery(document).ajaxSend Frosting.wrap (event, jqXHR, options) ->
          jqXHR.startTime = now()

          # This is super sketchy (it relies on the below function being called
          # synchronously after this one), but it's jQuery's fault for
          # not giving us a reference to the xhr object.
          lastXHR = jqXHR

        jQuery.ajaxSettings.xhr = ->
          # jQuery gives us no reference to the built-in xhr object, so
          # we have to override how it creates the object to be able to bind our
          # timer.
          try
            xhr = new XMLHttpRequest()
          catch e

          # We seperatly frost this, because it's critical that even if
          # it fails, this function still returns the xhr object.
          Frosting.run ->
            xhr?.readyStateTimes =
              0: now()

            lastXHR?.realXHR = xhr
            lastXHR = null
            xhr?.addEventListener 'readystatechange', ->
              xhr.readyStateTimes[xhr.readyState] = now()

          return xhr

        self = this
        jQuery(document).ajaxComplete Frosting.wrap (event, xhr, options) ->
          # Skip our own sends to not continually send forever.  The request duration is
          # independently logged as bucky.latency.
          return if options._buckySend
          
          if xhr.startTime?
            dur = now() - xhr.startTime
          else
            if WARN_UNSTARTED_REQUEST
              hlog "A request was completed which Bucky did not record having been started.  Is bucky.request.monitor being called too late?"

            WARN_UNSTARTED_REQUEST = false
            return

          url = options.url
          url = self.getFullUrl url
          stat = self.urlToKey url, options.type, root

          send(stat, dur, 'timer')

          self.sendReadyStateTimes stat, xhr.realXHR?.readyStateTimes

          if xhr?.status?
            if xhr?.status > 12000
              # Most browsers return status code 0 for aborted/failed requests.  IE returns
              # special status codes over 12000: http://msdn.microsoft.com/en-us/library/aa383770%28VS.85%29.aspx
              #
              # We'll track the 12xxx code, but also store it as a 0
              count("#{ stat }.0")

            else if xhr.status isnt 0
              count("#{ stat }.#{ xhr.status.toString().charAt(0) }xx")

            count("#{ stat }.#{ xhr.status }")
    }

    nextMakeClient = (nextPrefix='') ->
      path = _.filter([prefix, nextPrefix], _.identity).join('.')
      makeClient(path)

    exports = {
      send,
      count,
      timer,
      now,
      requests,
      sendPerformanceData,
      flush,
      history: HISTORY,
      active: ACTIVE,
      enableAjaxMonitoring: _.bind(requests.monitor, requests)
    }

    _.map([exports, exports.timer, exports.requests], Frosting.wrap)

    _.extend nextMakeClient, exports

  exports = makeClient()

  module?.promise?.resolve exports
  exports

if window?
  # Using HS Static
  hubspot.define 'hubspot.bucky.client', ['enviro', '_', 'jQuery', 'hubspot.buttercream.frosting'], exportDef
else
  # Using CommonJS
  module.exports = exportDef(require('enviro'), require('underscore'), require('jquery'), require('buttercream'))
