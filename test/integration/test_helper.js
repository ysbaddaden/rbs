(function (g) {
  g.assert = require("minitest").assert;
  g.refute = require("minitest").refute;
}(typeof global === "undefined" ? window : global));
