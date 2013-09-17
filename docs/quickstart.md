```javascript
// Make sure you have included bucky.js or bucky.min.js on your page

Bucky.setOptions({
  host: "/bucky"
});

Bucky.sendPagePerformance('my.app.here.page');
Bucky.requests.monitor('my.app.here.requests');
```
