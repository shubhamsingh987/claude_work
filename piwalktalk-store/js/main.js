(function () {
  "use strict";

  var WHATSAPP_NUMBER = "919884625747"; // +91 98846 25747
  var DEFAULT_MESSAGE = "Hi! I'm interested in PiWalkTalk (₹2999 for a pair). Can you share more details?";

  function waLink(message) {
    var text = encodeURIComponent(message || DEFAULT_MESSAGE);
    return "https://wa.me/" + WHATSAPP_NUMBER + "?text=" + text;
  }

  var links = [
    { id: "nav-cta", message: DEFAULT_MESSAGE },
    { id: "hero-cta", message: "Hi! I'd like to order a PiWalkTalk pair (₹2999)." },
    { id: "price-cta", message: "Hi! I'd like to order a PiWalkTalk pair (₹2999). Is it in stock?" },
    { id: "footer-cta", message: DEFAULT_MESSAGE },
    { id: "fab-cta", message: DEFAULT_MESSAGE }
  ];

  links.forEach(function (item) {
    var el = document.getElementById(item.id);
    if (el) el.href = waLink(item.message);
  });

  var header = document.querySelector(".site-header");
  var toggle = document.getElementById("menu-toggle");
  if (toggle && header) {
    toggle.addEventListener("click", function () {
      var open = header.classList.toggle("nav-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });

    document.querySelectorAll(".site-nav-mobile a").forEach(function (link) {
      link.addEventListener("click", function () {
        header.classList.remove("nav-open");
        toggle.setAttribute("aria-expanded", "false");
      });
    });
  }
})();
