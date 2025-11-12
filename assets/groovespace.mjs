(function(){
  function fitPerspective(wrap){
    const tilt  = parseFloat(wrap.dataset.tilt  || 70);
    const persp = parseFloat(wrap.dataset.persp || 600);

    // ensure wrapper has the camera + origin centered
    wrap.style.setProperty('--persp', `${persp}px`);
    wrap.style.perspectiveOrigin = '50% 0%';

    let inner = wrap.querySelector(':scope > .perspinner');
    if(!inner){
      inner = document.createElement('div');
      inner.className = 'perspinner';
      const child = wrap.firstElementChild;
      wrap.appendChild(inner);
      inner.appendChild(child);
    }

    inner.style.transform = 'none';
    wrap.style.height = 'auto';
    const h = inner.getBoundingClientRect().height;
    const rad = tilt * Math.PI / 180;
    wrap.style.height = (h * Math.cos(rad)) + 'px';
    inner.style.transform = ` rotateY(15deg) rotateX(${tilt}deg) `; // camera on wrapper
  }

  function init(){ document.querySelectorAll('.perspwrap').forEach(fitPerspective); }
  addEventListener('load', init);
  addEventListener('resize', init);
})();
