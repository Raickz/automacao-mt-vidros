// Fora do Flutter, carregado antes dele: tela de carregamento, service worker
// e aviso de versão nova. Sem scripts inline (a página tem CSP).
(function () {
  // A tela de carregamento (logo) some quando o Flutter desenha o 1º quadro.
  window.addEventListener('flutter-first-frame', function () {
    var s = document.getElementById('splash');
    if (s) {
      s.style.opacity = '0';
      setTimeout(function () { s.remove(); }, 250);
    }
  });

  if (!('serviceWorker' in navigator)) return;

  function showUpdate(worker) {
    if (document.getElementById('update-bar')) return;
    var bar = document.createElement('div');
    bar.id = 'update-bar';
    bar.setAttribute('role', 'status');
    var text = document.createElement('span');
    text.textContent = 'Nova versão do app disponível.';
    var btn = document.createElement('button');
    btn.type = 'button';
    btn.textContent = 'Atualizar';
    btn.addEventListener('click', function () {
      btn.disabled = true;
      worker.postMessage('skipWaiting');
    });
    bar.appendChild(text);
    bar.appendChild(btn);
    document.body.appendChild(bar);
  }

  var reloading = false;
  navigator.serviceWorker.addEventListener('controllerchange', function () {
    if (reloading) return;
    reloading = true;
    window.location.reload();
  });

  window.addEventListener('load', function () {
    navigator.serviceWorker.register('sw.js').then(function (reg) {
      // Só avisa quando já havia uma versão rodando (não na 1ª instalação).
      if (reg.waiting && navigator.serviceWorker.controller) showUpdate(reg.waiting);
      reg.addEventListener('updatefound', function () {
        var w = reg.installing;
        if (!w) return;
        w.addEventListener('statechange', function () {
          if (w.state === 'installed' && navigator.serviceWorker.controller) showUpdate(w);
        });
      });
      // App aberto por muito tempo (PWA): procura versão nova a cada hora.
      setInterval(function () { reg.update().catch(function () {}); }, 60 * 60 * 1000);
    }).catch(function () {});
  });
})();
