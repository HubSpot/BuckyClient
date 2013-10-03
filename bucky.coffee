isServer = module? and not window?.module

if isServer
  {XMLHttpRequest} = require('xmlhttprequest')

  now = ->
    time = process.hrtime()
    (time[0] + time[1] / 1e9) * 1000

else
  now = ->
    window.performance?.now?() ? (+new Date)

# This is used if we can't get the navigationStart time from
# window.performance
initTime = +new Date

extend = (a, objs...) ->
  for obj in objs.reverse()
    for key, val of obj
      a[key] = val
  a

log = (msgs...) ->
  if console?.log?.call?
    console.log msgs...

log.error = (msgs...) ->
  if console?.error?.call?
    console.error msgs...

exportDef = ->
  defaults =
    # Where is the Bucky server hosted.  This should be both the host and the APP_ROOT (if you've
    # defined one).  This default assumes its at the same host as your app.
    #
    # Keep in mind that if you use a different host, CORS will come into play.
    host: '/bucky'

    # The max time we should wait between sends
    maxInterval: 30000

    # How long we should wait from getting the last datapoint
    # to do a send, if datapoints keep coming in eventually
    # the MAX_INTERVAL will trigger a send.
    aggregationInterval: 5000

    # How many decimal digits should we include in our
    # times?
    decimalPrecision: 3

    # Bucky can automatically report a datapoint of what its response time
    # is.  This is useful because Bucky returns almost immediately, making
    # it's response time a good measure of the user's connection latency.
    sendLatency: false

    # Downsampling will cause Bucky to only send data 100*SAMPLE percent
    # of the time.  It is used to reduce the amount of data sent to the backend.
    #
    # It's not done per datapoint, but per client, so you probably don't want to downsample
    # on node (you would be telling a percentage of your servers to not send data).
    sample: 1

    # Set to false to disable sends (in dev mode for example)
    active: true

  tagOptions = {}
  if not isServer
    $tag = document.querySelector('[data-bucky-host],[data-bucky-page],[data-bucky-requests]')
    if $tag
      tagOptions = {
        host: $tag.getAttribute('data-bucky-host')

        # These are to allow you to send page peformance data without having to manually call
        # the methods.
        pagePerformanceKey: $tag.getAttribute('data-bucky-page')
        requestsKey: $tag.getAttribute('data-bucky-requests')
      }

      for key in ['pagePerformanceKey', 'requestsKey']
        if tagOptions[key]?.toString().toLowerCase() is 'true' or tagOptions[key] is ''
          tagOptions[key] = true
        else if tagOptions[key]?.toString().toLowerCase is 'false'
          tagOptions[key] = null
   
  options = extend {}, defaults, tagOptions
    
  TYPE_MAP =
    'timer': 'ms'
    'gauge': 'g'
    'counter': 'c'

  ACTIVE = options.active
  do updateActive = ->
    ACTIVE = options.active and Math.random() < options.sample

  HISTORY = []

  setOptions = (opts) ->
    extend options, opts

    if 'sample' of opts or 'active' of opts
      updateActive()

    options

  round = (num, precision=options.decimalPrecision) ->
    Math.round(num * Math.pow(10, precision)) / Math.pow(10, precision)

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

    queue[path] = {value, type, count}

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
    sendTimeout = setTimeout flush, options.aggregationInterval

    unless maxTimeout?
      maxTimeout = setTimeout flush, options.maxInterval

  makeRequest = (data) ->
    corsSupport = isServer or (window.XMLHttpRequest and (window.XMLHttpRequest.defake or 'withCredentials' of new window.XMLHttpRequest()))

    if isServer
      sameOrigin = true
    else
      match = /^(https?:\/\/[^\/]+)/i.exec options.host

      if match
        # FQDN

        origin = match[1]
        if origin is "#{ document.location.protocol }//#{ document.location.host }"
          sameOrigin = true
        else
          sameOrigin = false
      else
        # Relative URL
        
        sameOrigin = true

    sendStart = now()
  
    body = ''
    for name, val of data
      body += "#{ name }:#{ val }\n"

    if not sameOrigin and not corsSupport and window?.XDomainRequest?
      # CORS support for IE9
      req = new window.XDomainRequest
    else
      req = new (window?.XMLHttpRequest ? XMLHttpRequest)

    # Don't track this request with Bucky, as we'd be tracking our own
    # sends forever.  The latency of this request is independently tracked
    # by updateLatency.
    req.bucky = {track: false}

    req.open 'POST', "#{ options.host }/v1/send", true

    req.setRequestHeader 'Content-Type', 'text/plain'

    req.addEventListener 'load', ->
      updateLatency(now() - sendStart)
    , false

    req.send body

    req

  sendQueue = ->
    if not ACTIVE
      log "Would send bucky queue"
      return

    out = {}
    for key, point of queue
      HISTORY.push
        path: key
        count: point.count
        type: point.type
        value: point.value

      unless TYPE_MAP[point.type]?
        log.error "Type #{ point.type } not understood by Bucky"
        continue

      value = point.value
      if point.type in ['gauge', 'timer']
        value = round(value)

      out[key] = "#{ value }|#{ TYPE_MAP[point.type] }"

      if point.count isnt 1
        out[key] += "@#{ round(1 / point.count, 5) }"

    makeRequest out

    queue = {}

  latencySent = false
  updateLatency = (time) ->
    Bucky.latency = time

    if options.sendLatency and not latencySent
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
        prefix + '.' + path
      path

    send = (path, value, type='gauge') ->
      if not value? or not path?
        log.error "Can't log #{ path }:#{ value }"
        return

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
          log.error "Timer #{ path } ended without having been started"
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
          _now = now
          start = _now()

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
    sendPagePerformance = (path) ->
      return false unless window?.performance?.timing?
      return false if sentPerformanceData

      if not path or path is true
        path = requests.urlToKey(document.location.toString()) + '.page'

      if document.readyState in ['uninitialized', 'loading']
        # The data isn't fully ready until document load
        document.addEventListener? 'DOMContentLoaded', =>
          sendPagePerformance.call(@, path)
        , false

        return false

      sentPerformanceData = true

      start = window.performance.timing.navigationStart
      for key, time of window.performance.timing when time
        timer.send "#{ path }.#{ key }", (time - start)

      return true

    requests = {
      transforms:
        mapping:
          guid: /\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig
          sha1: /\/[0-9a-f]{40}/ig
          md5: /\/[0-9a-f]{32}/ig
          id: /\/[0-9;_\-]+/g
          email: /\/[^/]+@[^/]+/g
          domain: [/\/[^/]+\.[a-z]{2,3}\//ig, '/']

        enabled: ['guid', 'sha1', 'md5', 'id', 'email', 'domain']

        enable: (name, test, replacement='') ->
          if test?
            @mapping[name] = [test, replacement]

          @enabled.splice 0, 0, name

        disable: (name) ->
          for val, i of @enabled
            if val is name
              @enabled.splice i, 1
              return

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
          timer.send "#{ path }.#{ status }", val

      urlToKey: (url, type, root) ->
        url = url.replace /https?:\/\//i, ''

        parsedUrl = /([^/:]*)(?::\d+)?(\/[^\?#]*)?.*/i.exec(url)
        host = parsedUrl[1]
        path = parsedUrl[2] ? ''

        for mappingName in requests.transforms.enabled
          mapping = requests.transforms.mapping[mappingName]

          if not mapping?
            log.error "Bucky Error: Attempted to enable a mapping which is not defined: #{ mappingName }"
            continue

          if typeof mapping is 'function'
            path = mapping path, url, type, root
            continue

          if mapping instanceof RegExp
            mapping = [mapping, '']

          path = path.replace(mapping[0], mapping[1])

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

      monitor: (root) ->
        if not root or root is true
          root = requests.urlToKey(document.location.toString()) + '.requests'

        self = this
        done = ({type, url, event, request, readyStateTimes, startTime}) ->
          if startTime?
            dur = now() - startTime
          else
            return

          url = self.getFullUrl url
          stat = self.urlToKey url, type, root

          send(stat, dur, 'timer')

          self.sendReadyStateTimes stat, readyStateTimes

          if request?.status?
            if request.status > 12000
              # Most browsers return status code 0 for aborted/failed requests.  IE returns
              # special status codes over 12000: http://msdn.microsoft.com/en-us/library/aa383770%28VS.85%29.aspx
              #
              # We'll track the 12xxx code, but also store it as a 0
              count("#{ stat }.0")

            else if request.status isnt 0
              count("#{ stat }.#{ request.status.toString().charAt(0) }xx")

            count("#{ stat }.#{ request.status }")

        _XMLHttpRequest = window.XMLHttpRequest
        window.XMLHttpRequest = ->
          req = new _XMLHttpRequest

          try
            startTime = null
            readyStateTimes = {}

            _open = req.open
            req.open = (type, url, async) ->
              try
                readyStateTimes[0] = now()

                req.addEventListener 'readystatechange', ->
                  readyStateTimes[req.readyState] = now()
                , false

                req.addEventListener 'loadend', (event) ->
                  if not req.bucky? or req.bucky.track isnt false
                    done {type, url, event, startTime, readyStateTimes, request: req}
                , false
              catch e
                log.error "Bucky error monitoring XHR open call", e

              _open.apply req, arguments

            _send = req.send
            req.send = ->
              startTime = now()

              _send.apply req, arguments
          catch e
            log.error "Bucky error monitoring XHR", e

          req
    }

    nextMakeClient = (nextPrefix='') ->
      path = prefix ? ''
      path += '.' if path and nextPrefix
      path += nextPrefix if nextPrefix

      makeClient(path)

    exports = {
      send,
      count,
      timer,
      now,
      requests,
      sendPagePerformance,
      flush,
      setOptions,
      options,
      history: HISTORY,
      active: ACTIVE
    }

    for key, val of exports
      nextMakeClient[key] = val

    nextMakeClient

  client = makeClient()

  if options.pagePerformanceKey
    client.sendPagePerformance(options.pagePerformanceKey)

  if options.requestsKey
    client.requests.monitor(options.requestsKey)

  client

if typeof define is 'function' and define.amd
  # AMD
  define exportDef
else if typeof exports is 'object'
  # Node
  module.exports = exportDef()
else
  # Global
  window.Bucky = exportDef()
