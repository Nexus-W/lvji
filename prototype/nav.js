/* 统一导航
   目标：从哪来，回哪去；并把上下文（比如 trip=xx）一路带下去。

   机制：
   1. 每打开一个页面，把自己的完整 URL（含参数）压进 sessionStorage 的栈
   2. 带 data-back 的返回键：回到栈里上一个不同的页面（能精确还原参数）
   3. 栈不可用时，退化成 ?from= 参数
   4. 页内链接自动继承除 from 外的查询参数（例如 trip） */
(function(){
  'use strict';

  var KEY = 'tripnest.nav';
  var cur = location.href;
  var here = location.pathname.split('/').pop() || 'trips.html';

  function readStack(){
    try { return JSON.parse(sessionStorage.getItem(KEY) || '[]') || []; }
    catch(e){ return []; }
  }
  function writeStack(st){
    try { sessionStorage.setItem(KEY, JSON.stringify(st)); } catch(e){}
  }

  /* ---- 1. 入栈 ---- */
  var stack = readStack();
  if(stack[stack.length - 1] !== cur) stack.push(cur);
  if(stack.length > 40) stack = stack.slice(-40);
  writeStack(stack);

  /* ---- 2. 解析当前参数（from 不参与继承） ---- */
  var carry = {};
  (location.search || '').replace(/^\?/, '').split('&').forEach(function(kv){
    if(!kv) return;
    var i = kv.indexOf('=');
    var k = i < 0 ? kv : kv.slice(0, i);
    if(k === 'from') return;
    carry[k] = i < 0 ? '' : kv.slice(i + 1);
  });

  /* ---- 3. 返回键 ---- */
  var backs = document.querySelectorAll('[data-back]');
  for(var i = 0; i < backs.length; i++){
    backs[i].addEventListener('click', function(ev){
      if(ev.metaKey || ev.ctrlKey || ev.shiftKey) return;
      ev.preventDefault();
      var def = this.getAttribute('data-back');

      var st = readStack();
      var idx = -1;
      for(var j = st.length - 1; j >= 0; j--){
        if(st[j] !== cur){ idx = j; break; }
      }
      if(idx >= 0){
        var target = st[idx];
        st.length = idx + 1;
        writeStack(st);
        location.href = target;
        return;
      }
      /* 退化：用 from 参数 */
      var m = /[?&]from=([^&]*)/.exec(location.search || '');
      if(m){
        var f = decodeURIComponent(m[1]);
        if(/^[a-z0-9_\-]+\.html$/i.test(f) && f !== here){
          location.href = f;
          return;
        }
      }
      location.href = def;
    });
  }

  /* ---- 4. 页内链接继承上下文 ---- */
  var links = document.querySelectorAll('a[href]');
  for(var k = 0; k < links.length; k++){
    var a = links[k];
    if(a.hasAttribute('data-back')) continue;
    var h = a.getAttribute('href');
    if(!h || h.indexOf('://') >= 0 || h.charAt(0) === '#') continue;
    if(!/\.html(\?|$)/.test(h)) continue;

    var parts = h.split('?');
    var path = parts[0];
    var qs = parts[1] || '';
    var names = qs.split('&').filter(Boolean).map(function(kv){ return kv.split('=')[0]; });

    var add = [];
    for(var key in carry){
      if(names.indexOf(key) < 0) add.push(key + '=' + carry[key]);
    }
    if(names.indexOf('from') < 0) add.push('from=' + encodeURIComponent(here));

    if(add.length){
      qs = qs ? (qs + '&' + add.join('&')) : add.join('&');
    }
    a.setAttribute('href', path + (qs ? '?' + qs : ''));
  }

  /* ---- 5. 页面转场：进场淡入上浮，出场轻微上移淡出 ---- */
  var reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  if(!reduce){
    var st = document.createElement('style');
    st.textContent = [
      '@keyframes pgIn{from{opacity:0;transform:translateY(10px) scale(.996)}',
      '  to{opacity:1;transform:none}}',
      '.pg-enter .app{animation:pgIn .28s cubic-bezier(.22,1,.36,1) both}',
      '.pg-leave .app{opacity:0;transform:translateY(-6px);',
      '  transition:opacity .15s ease,transform .15s ease}'
    ].join('');
    document.head.appendChild(st);

    document.documentElement.classList.add('pg-enter');
    setTimeout(function(){ document.documentElement.classList.remove('pg-enter'); }, 320);

    var links2 = document.querySelectorAll('a[href$=".html"], a[href*=".html?"]');
    for(var n = 0; n < links2.length; n++){
      (function(a){
        if(a.hasAttribute('data-back')) return;
        a.addEventListener('click', function(ev){
          if(ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.button !== 0) return;
          var href = a.getAttribute('href');
          if(!href || href.indexOf('://') >= 0) return;
          ev.preventDefault();
          document.documentElement.classList.add('pg-leave');
          setTimeout(function(){ location.href = href; }, 150);
        });
      })(links2[n]);
    }
  }
})();
