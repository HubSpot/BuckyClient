hubspot.define 'hubspot.bucky.spitfire', ['_', 'hubspot.bucky.client', 'hubspot.spitfire.client'], (_, Bucky, Spitfire) ->
  monitor = (root='requests') ->
    Spitfire.on 'failure', ->
      Bucky.count "#{ root }.spitfire.failure"

    Spitfire.on 'success', ->
      Bucky.count "#{ root }.spitfire.success"

    Spitfire.on 'resolve', ({deferred, timing, resp, options}) ->
      url = Bucky.requests.getFullUrl options.url
      key = Bucky.requests.urlToKey url, (options.type or 'GET'), root

      Bucky.timer.send key, (timing.complete - timing.enqueue)
      Bucky.timer.send "#{ key }.queued", (timing.request - timing.enqueue)
      Bucky.timer.send "#{ key }.pending", (timing.complete - timing.request)
      Bucky.timer.send "#{ key }.latency", (timing.complete - timing.request - resp.headers['x-spitfire-duration'])

      Bucky.count "#{ key }.#{ resp.status }"
      Bucky.count "#{ key }.spitfire"

  {monitor}
