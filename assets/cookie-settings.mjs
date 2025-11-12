// assets/cookie-settings.mjs

// /assets/cookie-settings.mjs
console.log("[cookie-settings] module loaded");

export function openCookieSettings() {
  console.log("[cookie-settings] openCookieSettings() → called");
  // Cookiebot ready?
  if (window.Cookiebot && typeof window.Cookiebot.renew === "function") {
    console.log("[cookie-settings] Cookiebot.renew()");
    window.Cookiebot.renew();
    return true;
  }

  // Generic IAB TCF (some CMPs)
  if (typeof window.__tcfapi === "function") {
    console.log("[cookie-settings] __tcfapi displayConsentUi");
    window.__tcfapi("displayConsentUi", 2, () => {});
    return true;
  }

  // Not ready yet — wait for Cookiebot to finish initializing
  console.warn("[cookie-settings] CMP not ready; waiting for CookiebotOnLoad");
  window.addEventListener(
    "CookiebotOnLoad",
    () => {
      console.log("[cookie-settings] CookiebotOnLoad → renew()");
      window.Cookiebot?.renew?.();
    },
    { once: true }
  );
  return false;
}

function initCookieSettings() {
  const btn = document.getElementById("cookie-settings");
  console.log("[cookie-settings] init; link =", btn);
  if (!btn) return;
  btn.addEventListener("click", (e) => {
    e.preventDefault();
    openCookieSettings();
  });
}

// Works whether loaded in head or after body
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", initCookieSettings, { once: true });
} else {
  initCookieSettings();
}
