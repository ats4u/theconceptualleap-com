
document.addEventListener("DOMContentLoaded", () => {
  document.querySelectorAll(".ats4u-twitter-video").forEach((el) => {
    const twitterId = (el.innerText)?.replaceAll?.( "x.com", "twitter.com" );
    if (twitterId !== null) {
      el.outerHTML = (`<blockquote class="twitter-tweet center-box" data-conversation="none" data-media-max-width="560"><a href="${twitterId}">${twitterId}</a></blockquote>` );
    }
  });
});
