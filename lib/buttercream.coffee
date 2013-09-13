define = ->
  run = (fn, args=[], ctx) ->
    if process?.env?.BUTTERCREAM_DEBUG or window?.localStorage?.BUTTERCREAM_DEBUG or window?.BUTTERCREAM_DEBUG
      return fn.apply (ctx ? @), args
    else
      try
        return fn.apply (ctx ? @), args
      catch e
        console?.error "Buttercream frosted over an error", e

  wrapFunction = (fn) ->
    return fn if fn._frosted

    out = ->
      run(fn, arguments, @)

    out._frosted = true

    out

  wrapObject = (obj) ->
    out = {}

    for key, el of obj
      if typeof el is 'function'
        out[key] = wrapFunction el
      else
        out[key] = el
        
    out

  wrap = (obj) ->
    if typeof obj is 'function'
      wrapFunction obj
    else if obj === Object(obj)
      wrapObject obj
    else
      obj

  {wrap, run, frost: wrap, wrapFunction, wrapObject}

if module? and not window?.module
  module.exports = define()
else
  window.Buttercream = define()
