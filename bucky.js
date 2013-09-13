(function() {
  var exportDef, initTime, now,
    __slice = [].slice;

  if ((typeof process !== "undefined" && process !== null ? process.hrtime : void 0) != null) {
    now = function() {
      var time;
      time = process.hrtime();
      return (time[0] + time[1] / 1e9) * 1000;
    };
  } else {
    now = function() {
      var _ref, _ref1;
      return (_ref = (_ref1 = window.performance) != null ? typeof _ref1.now === "function" ? _ref1.now() : void 0 : void 0) != null ? _ref : +(new Date);
    };
  }

  initTime = +(new Date);

  exportDef = function(Env, _, $, Frosting) {
    var ACTIVE, AGGREGATION_INTERVAL, BUCKY_HOST, DECIMAL_PRECISION, HISTORY, HOSTS, MAX_INTERVAL, SAMPLE, SEND_LATENCY, TYPE_MAP, WARN_UNSTARTED_REQUEST, considerSending, currentLatency, enqueue, exports, flush, latencySent, makeClient, maxTimeout, queue, round, sendQueue, sendTimeout, updateLatency, _ref, _ref1;
    MAX_INTERVAL = 30000;
    AGGREGATION_INTERVAL = 5000;
    DECIMAL_PRECISION = 3;
    SEND_LATENCY = true;
    SAMPLE = 1;
    TYPE_MAP = {
      'timer': 'ms',
      'gauge': 'g',
      'counter': 'c'
    };
    HOSTS = {
      'prod': 'https://app.hubspot.com/bucky',
      'qa': 'https://app.hubspotqa.com/bucky'
    };
    BUCKY_HOST = (_ref = HOSTS[Env.getInternal('api.bucky')]) != null ? _ref : HOSTS.qa;
    ACTIVE = Math.random() < SAMPLE;
    WARN_UNSTARTED_REQUEST = true;
    HISTORY = {};
    round = function(num, precision) {
      if (precision == null) {
        precision = DECIMAL_PRECISION;
      }
      return num.toFixed(precision);
    };
    queue = {};
    enqueue = function(path, value, type) {
      var count, _ref1;
      if (!ACTIVE) {
        return;
      }
      count = 1;
      if (path in queue) {
        if (type === 'counter') {
          value += queue[path].value;
        } else {
          count = (_ref1 = queue[path].count) != null ? _ref1 : count;
          count++;
          value = queue[path].value + (value - queue[path].value) / count;
        }
      }
      HISTORY[path] = queue[path] = {
        value: value,
        type: type,
        count: count
      };
      return considerSending();
    };
    sendTimeout = null;
    maxTimeout = null;
    flush = function() {
      clearTimeout(sendTimeout);
      clearTimeout(maxTimeout);
      maxTimeout = null;
      sendTimeout = null;
      return sendQueue();
    };
    considerSending = function() {
      clearTimeout(sendTimeout);
      sendTimeout = setTimeout(flush, AGGREGATION_INTERVAL);
      if (maxTimeout == null) {
        return maxTimeout = setTimeout(flush, MAX_INTERVAL);
      }
    };
    sendQueue = function() {
      var key, out, point, sendStart, value, _ref1;
      if (!(typeof Env.deployed === "function" ? Env.deployed('bucky') : void 0)) {
        return;
      }
      out = {};
      for (key in queue) {
        point = queue[key];
        if (TYPE_MAP[point.type] == null) {
          console.error("Type " + point.type + " not understood by Bucky");
          continue;
        }
        if (point.type === 'timer' && point.value > 120000) {
          continue;
        }
        value = point.value;
        if ((_ref1 = point.type) === 'gauge' || _ref1 === 'timer') {
          value = round(value);
        }
        out[key] = "" + value + "|" + TYPE_MAP[point.type];
        if (point.count !== 1) {
          out[key] += "@" + (round(1 / point.count, 5));
        }
      }
      sendStart = now();
      $.ajax({
        url: BUCKY_HOST + '/send',
        type: 'POST',
        contentType: 'application/json',
        data: JSON.stringify(out),
        _buckySend: true,
        error: function(e) {
          return console.error(e, "sending data");
        },
        success: function() {
          var sendEnd;
          sendEnd = now();
          return updateLatency(sendEnd - sendStart);
        }
      });
      return queue = {};
    };
    ({
      getHistory: function() {
        return HISTORY;
      }
    });
    currentLatency = 0;
    latencySent = false;
    updateLatency = function(time) {
      currentLatency = time;
      if (SEND_LATENCY && !latencySent) {
        enqueue('bucky.latency', time, 'timer');
        latencySent = true;
        return setTimeout(function() {
          return latencySent = false;
        }, 5 * 60 * 1000);
      }
    };
    makeClient = function(prefix) {
      var buildPath, count, exports, nextMakeClient, requests, send, sendPerformanceData, sentPerformanceData, timer;
      if (prefix == null) {
        prefix = '';
      }
      buildPath = function(path) {
        if (prefix != null ? prefix.length : void 0) {
          path = prefix + '.' + path;
        }
        return path.replace('.ENV.', "." + (Env.getInternal('bucky')) + ".");
      };
      send = function(path, value, type) {
        if (type == null) {
          type = 'gauge';
        }
        return enqueue(buildPath(path), value, type);
      };
      timer = {
        TIMES: {},
        send: function(path, duration) {
          return send(path, duration, 'timer');
        },
        time: function() {
          var action, args, ctx, done, path,
            _this = this;
          path = arguments[0], action = arguments[1], ctx = arguments[2], args = 4 <= arguments.length ? __slice.call(arguments, 3) : [];
          timer.start(path);
          done = function() {
            return timer.stop(path);
          };
          args.splice(0, 0, done);
          return action.apply(ctx, args);
        },
        timeSync: function() {
          var action, args, ctx, path, ret;
          path = arguments[0], action = arguments[1], ctx = arguments[2], args = 4 <= arguments.length ? __slice.call(arguments, 3) : [];
          timer.start(path);
          ret = action.apply(ctx, args);
          timer.stop(path);
          return ret;
        },
        wrap: function(path, action) {
          if (action != null) {
            return function() {
              var args;
              args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
              return timer.timeSync.apply(timer, [path, action, this].concat(__slice.call(args)));
            };
          } else {
            return function(action) {
              return function() {
                var args;
                args = 1 <= arguments.length ? __slice.call(arguments, 0) : [];
                return timer.timeSync.apply(timer, [path, action, this].concat(__slice.call(args)));
              };
            };
          }
        },
        start: function(path) {
          return timer.TIMES[path] = now();
        },
        stop: function(path) {
          var duration;
          if (timer.TIMES[path] == null) {
            console.error("Timer " + path + " ended without having been started");
            return;
          }
          duration = now() - timer.TIMES[path];
          timer.TIMES[path] = void 0;
          return timer.send(path, duration);
        },
        stopwatch: function(prefix, start) {
          var last, _now;
          if (start != null) {
            _now = function() {
              return +(new Date);
            };
          } else {
            start = now();
            _now = now;
          }
          last = start;
          return {
            mark: function(path, offset) {
              var end;
              if (offset == null) {
                offset = 0;
              }
              end = _now();
              if (prefix) {
                path = prefix + '.' + path;
              }
              return timer.send(path, end - start + offset);
            },
            split: function(path, offset) {
              var end;
              if (offset == null) {
                offset = 0;
              }
              end = _now();
              if (prefix) {
                path = prefix + '.' + path;
              }
              timer.send(path, end - last + offset);
              return last = end;
            }
          };
        },
        mark: function(path, time) {
          var start;
          if (time == null) {
            time = +(new Date);
          }
          start = timer.navigationStart();
          return timer.send(path, time - start);
        },
        navigationStart: function() {
          var _ref1, _ref2, _ref3;
          return (_ref1 = typeof window !== "undefined" && window !== null ? (_ref2 = window.performance) != null ? (_ref3 = _ref2.timing) != null ? _ref3.navigationStart : void 0 : void 0 : void 0) != null ? _ref1 : initTime;
        },
        responseEnd: function() {
          var _ref1, _ref2, _ref3;
          return (_ref1 = typeof window !== "undefined" && window !== null ? (_ref2 = window.performance) != null ? (_ref3 = _ref2.timing) != null ? _ref3.responseEnd : void 0 : void 0 : void 0) != null ? _ref1 : initTime;
        },
        now: function() {
          return now();
        }
      };
      count = function(path, count) {
        if (count == null) {
          count = 1;
        }
        return send(path, count, 'counter');
      };
      sentPerformanceData = false;
      sendPerformanceData = function(path) {
        var key, start, time, _ref1, _ref2, _ref3;
        if (path == null) {
          path = 'timing';
        }
        if ((typeof window !== "undefined" && window !== null ? (_ref1 = window.performance) != null ? _ref1.timing : void 0 : void 0) == null) {
          return false;
        }
        if (sentPerformanceData) {
          return false;
        }
        if ((_ref2 = document.readyState) === 'uninitialized' || _ref2 === 'loading') {
          if (typeof document.addEventListener === "function") {
            document.addEventListener('DOMContentLoaded', function() {
              return sendPerformanceData.apply(this, arguments);
            });
          }
          return;
        }
        sentPerformanceData = true;
        start = window.performance.timing.navigationStart;
        _ref3 = window.performance.timing;
        for (key in _ref3) {
          time = _ref3[key];
          if (time !== 0) {
            send("" + path + "." + key, time - start, 'timer');
          }
        }
        return true;
      };
      requests = {
        sendReadyStateTimes: function(path, times) {
          var code, codeMapping, diffs, last, status, time, val, _results;
          if (times == null) {
            return;
          }
          codeMapping = {
            1: 'sending',
            2: 'headers',
            3: 'waiting',
            4: 'receiving'
          };
          diffs = {};
          last = null;
          for (code in times) {
            time = times[code];
            if ((last != null) && (codeMapping[code] != null)) {
              diffs[codeMapping[code]] = time - last;
            }
            last = time;
          }
          _results = [];
          for (status in diffs) {
            val = diffs[status];
            _results.push(send("" + path + "." + status, val, 'timer'));
          }
          return _results;
        },
        urlToKey: function(url, type, root) {
          var host, parsedUrl, path, stat, _ref1;
          url = url.replace(/https?:\/\//i, '');
          parsedUrl = /([^/:]*)(?::\d+)?(\/[^\?#]*)?.*/i.exec(url);
          host = parsedUrl[1];
          path = (_ref1 = parsedUrl[2]) != null ? _ref1 : '';
          path = path.replace(/\/events?\/\w{8,12}/ig, '/events');
          path = path.replace(/\/campaigns?\/\w{15}(\w{3})?/ig, '/campaigns');
          path = path.replace(/\/_[^/]+/g, '');
          path = path.replace(/\.js$/, '');
          path = path.replace(/\/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/ig, '');
          path = path.replace(/\/[0-9a-f]{40}/ig, '');
          path = path.replace(/\/[0-9a-f]{32}/ig, '');
          path = path.replace(/\/[0-9;_\-]+/g, '');
          path = path.replace(/\/[^/]+@[^/]+/g, '');
          path = path.replace(/\/[^/]+\.[a-z]{2,3}/ig, '');
          path = path.replace(/\/static(\-\d+\.\d+)?/g, '/static');
          path = decodeURIComponent(path);
          path = path.replace(/[^a-zA-Z0-9\-\.\/ ]+/g, '_');
          stat = host + path.replace(/[\/ ]/g, '.');
          stat = stat.replace(/(^\.)|(\.$)/g, '');
          stat = stat.replace(/\.com/, '');
          stat = stat.replace(/www\./, '');
          if (root) {
            stat = root + '.' + stat;
          }
          if (type) {
            stat = stat + '.' + type.toLowerCase();
          }
          stat = stat.replace(/\.\./g, '.');
          return stat;
        },
        getFullUrl: function(url, location) {
          if (location == null) {
            location = document.location;
          }
          if (/^\//.test(url)) {
            return location.hostname + url;
          } else if (!/https?:\/\//i.test(url)) {
            return location.toString() + url;
          } else {
            return url;
          }
        },
        monitor: function(root) {
          var lastXHR, self;
          if (root == null) {
            root = 'requests';
          }
          lastXHR = void 0;
          jQuery(document).ajaxSend(Frosting.wrap(function(event, jqXHR, options) {
            jqXHR.startTime = now();
            return lastXHR = jqXHR;
          }));
          jQuery.ajaxSettings.xhr = function() {
            var e, xhr;
            try {
              xhr = new XMLHttpRequest();
            } catch (_error) {
              e = _error;
            }
            Frosting.run(function() {
              if (xhr != null) {
                xhr.readyStateTimes = {
                  0: now()
                };
              }
              if (lastXHR != null) {
                lastXHR.realXHR = xhr;
              }
              lastXHR = null;
              return xhr != null ? xhr.addEventListener('readystatechange', function() {
                return xhr.readyStateTimes[xhr.readyState] = now();
              }) : void 0;
            });
            return xhr;
          };
          self = this;
          return jQuery(document).ajaxComplete(Frosting.wrap(function(event, xhr, options) {
            var dur, stat, url, _ref1;
            if (options._buckySend) {
              return;
            }
            if (xhr.startTime != null) {
              dur = now() - xhr.startTime;
            } else {
              if (WARN_UNSTARTED_REQUEST) {
                hlog("A request was completed which Bucky did not record having been started.  Is bucky.request.monitor being called too late?");
              }
              WARN_UNSTARTED_REQUEST = false;
              return;
            }
            url = options.url;
            url = self.getFullUrl(url);
            stat = self.urlToKey(url, options.type, root);
            send(stat, dur, 'timer');
            self.sendReadyStateTimes(stat, (_ref1 = xhr.realXHR) != null ? _ref1.readyStateTimes : void 0);
            if ((xhr != null ? xhr.status : void 0) != null) {
              if ((xhr != null ? xhr.status : void 0) > 12000) {
                count("" + stat + ".0");
              } else if (xhr.status !== 0) {
                count("" + stat + "." + (xhr.status.toString().charAt(0)) + "xx");
              }
              return count("" + stat + "." + xhr.status);
            }
          }));
        }
      };
      nextMakeClient = function(nextPrefix) {
        var path;
        if (nextPrefix == null) {
          nextPrefix = '';
        }
        path = _.filter([prefix, nextPrefix], _.identity).join('.');
        return makeClient(path);
      };
      exports = {
        send: send,
        count: count,
        timer: timer,
        now: now,
        requests: requests,
        sendPerformanceData: sendPerformanceData,
        flush: flush,
        history: HISTORY,
        active: ACTIVE,
        enableAjaxMonitoring: _.bind(requests.monitor, requests)
      };
      _.map([exports, exports.timer, exports.requests], Frosting.wrap);
      return _.extend(nextMakeClient, exports);
    };
    exports = makeClient();
    if (typeof module !== "undefined" && module !== null) {
      if ((_ref1 = module.promise) != null) {
        _ref1.resolve(exports);
      }
    }
    return exports;
  };

  if (typeof window !== "undefined" && window !== null) {
    hubspot.define('hubspot.bucky.client', ['enviro', '_', 'jQuery', 'hubspot.buttercream.frosting'], exportDef);
  } else {
    module.exports = exportDef(require('enviro'), require('underscore'), require('jquery'), require('buttercream'));
  }

}).call(this);
