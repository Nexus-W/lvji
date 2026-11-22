/* 状态栏占位：所有页面顶部统一留出安全区
   主流 App 都会给系统状态栏留白，否则内容会被信号/电量条压住。
   这里用一段脚本统一注入，避免十个页面各写一遍。 */
(function(){
  'use strict';

  var app = document.querySelector('.app');
  if(!app) return;

  var css = [
    '.statusbar{flex:0 0 44px;height:44px;display:flex;align-items:center;',
    '  justify-content:space-between;padding:0 20px 0 22px;box-sizing:border-box;',
    '  background:var(--panel);color:var(--t1);position:relative;z-index:60;',
    '  font-size:12.5px;font-weight:600;letter-spacing:.2px;font-variant-numeric:tabular-nums}',
    '.statusbar .sb-r{display:flex;align-items:center;gap:5px}',
    '.statusbar svg{display:block}',
    '.statusbar .sb-bat{width:22px;height:11px;border:1.2px solid currentColor;border-radius:3px;',
    '  position:relative;opacity:.9}',
    '.statusbar .sb-bat::after{content:"";position:absolute;right:-3.5px;top:3px;width:2px;height:5px;',
    '  border-radius:0 1px 1px 0;background:currentColor}',
    '.statusbar .sb-bat i{position:absolute;left:1.4px;top:1.4px;bottom:1.4px;width:72%;',
    '  border-radius:1.5px;background:currentColor;display:block}',
    /* 内容里如果还有自己的顶栏，跟状态栏之间加一条细线会更清楚 */
    '.statusbar + .head{border-top:none}'
  ].join('\n');

  var style = document.createElement('style');
  style.textContent = css;
  document.head.appendChild(style);

  var d = new Date();
  var hh = d.getHours(), mm = d.getMinutes();
  var time = hh + ':' + (mm < 10 ? '0' + mm : mm);

  var bar = document.createElement('div');
  bar.className = 'statusbar';
  bar.innerHTML =
    '<span class="sb-t">' + time + '</span>' +
    '<span class="sb-r">' +
      '<svg width="17" height="11" viewBox="0 0 17 11" fill="none">' +
        '<rect x="0" y="7.5" width="3" height="3.5" rx="1" fill="currentColor"/>' +
        '<rect x="4.6" y="5.5" width="3" height="5.5" rx="1" fill="currentColor"/>' +
        '<rect x="9.2" y="3" width="3" height="8" rx="1" fill="currentColor"/>' +
        '<rect x="13.8" y="0.5" width="3" height="10.5" rx="1" fill="currentColor" opacity=".35"/>' +
      '</svg>' +
      '<svg width="15" height="11" viewBox="0 0 15 11" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">' +
        '<path d="M1 3.6a9.5 9.5 0 0 1 13 0"/>' +
        '<path d="M3.4 6.2a6 6 0 0 1 8.2 0"/>' +
        '<path d="M5.8 8.6a2.6 2.6 0 0 1 3.4 0"/>' +
      '</svg>' +
      '<span class="sb-bat"><i></i></span>' +
    '</span>';

  app.insertBefore(bar, app.firstChild);
})();
