/* 主题：读取设置里的「界面主题」，真的切换明暗
   放在 <head> 里执行，避免先闪一下深色再变浅 */
(function(){
  'use strict';

  var STORE = 'tripnest.settings';
  var s = {};
  try { s = JSON.parse(localStorage.getItem(STORE) || '{}') || {}; } catch(e){ s = {}; }

  var theme = s['界面主题'] || '始终深色';
  var light = theme === '始终浅色' ||
    (theme === '跟随系统' && window.matchMedia &&
     window.matchMedia('(prefers-color-scheme: light)').matches);

  window.__isLight = !!light;
  if(!light) return;

  var el = document.documentElement;
  el.classList.add('light');

  var css = document.createElement('style');
  css.textContent = [
    'html.light{--bg:#EDF0F5;--panel:#FFFFFF;--panel2:#F5F7FB;--line:#DCE3ED;',
    '  --t1:#16202B;--t2:#556171;--t3:#8792A0;--accent:#0F9C68;',
    '  --warn:#B26A00;--info:#3A63C8}',
    'html.light body{background:#EDF0F5;color:#16202B}',
    'html.light .device{background:#fff;border-color:#DCE3ED;',
    '  box-shadow:0 24px 60px -34px rgba(15,25,40,.42)}',
    'html.light .app{background:#fff}',
    'html.light .head,html.light .tabbar{background:rgba(255,255,255,.97);border-color:#E3E9F1}',
    'html.light .back,html.light .hbtn{background:#fff;border-color:#DCE3ED;color:#556171}',
    'html.light .card,html.light .trip,html.light .box,html.light .why{background:#fff}',
    'html.light .row{border-color:#EDF1F6}',
    'html.light .chip{border-color:#DCE3ED;color:#556171;background:#fff}',
    'html.light .chip.on{background:#16202B;color:#fff;border-color:#16202B}',
    'html.light .lb-card{background:#fff;border-color:#DCE3ED}',
    'html.light .lb-note{background:rgba(190,160,80,.14);border-color:rgba(150,120,40,.3);color:#6B5620}',
    'html.light .body{color:#3A4654}',
    'html.light .quote{color:#8A6D1F}',
    'html.light .jn{background:rgba(190,160,80,.12);border-color:rgba(150,120,40,.28)}',
    'html.light .sect,html.light .meta,html.light .unit,html.light .foot{color:#8792A0}',
    'html.light .hint{color:#8A95A3}',
    'html.light .sw{background:#D7DEE8}',
    'html.light .sw::after{background:#fff}',
    'html.light .sw.on{background:rgba(15,156,104,.28)}',
    'html.light .sw.on::after{background:#0F9C68;transform:translateX(16px)}',
    'html.light .ov{background:#fff;border-color:#E3E9F1}',
    'html.light .ovmap{border-color:#DCE3ED}',
    'html.light .days,html.light .p2days,html.light .chips{border-color:#E3E9F1}',
    'html.light .notice{background:rgba(255,180,84,.16);border-color:rgba(200,140,30,.35);color:#8A5B00}',
    'html.light .notice b{color:#7A4E00}',
    'html.light .datehead{background:linear-gradient(180deg,#fff 74%,rgba(255,255,255,0))}',
    'html.light .mask{background:rgba(20,30,45,.42)}',
    'html.light .pick{background:#fff;border-color:#E3E9F1}',
    'html.light .opt{border-color:#EDF1F6}',
    'html.light .pk-h{border-color:#E3E9F1}',
    'html.light .footer{background:#fff;border-color:#E3E9F1}',
    'html.light .clock{background:#fff}'
  ].join('\n');
  document.head.appendChild(css);
})();
