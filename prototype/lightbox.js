/* 统一大图组件：所有页面共用同一套模板与交互
   用法：
     Lightbox.open({
       sc, ar,            // 场景样式、宽高比
       title,             // 标题行文字
       noteKey,           // 备注唯一键（null 则不存）
       noteDefault,       // 无备注时的默认文案
       feat: {on, toggle} // 精选状态与切换函数
       cover,             // 设为封面回调
       onDelete           // 删除回调
     });
   依赖：data.js 的 noteGet / noteSet（没有则自动降级为不持久化） */
(function(){
  'use strict';

  var CSS = [
    '.lbx{position:absolute;inset:0;z-index:200;background:rgba(3,6,9,.94);backdrop-filter:blur(10px);',
    '  display:none;align-items:center;justify-content:center;padding:24px}',
    '.lbx.show{display:flex}',
    '.lbx-card{width:min(340px,86vw);border-radius:16px;overflow:hidden;background:var(--panel2);',
    '  border:1px solid rgba(255,255,255,.1);box-shadow:0 30px 60px -20px #000;',
    '  max-height:90vh;display:flex;flex-direction:column}',
    '.lbx-img{position:relative;overflow:hidden;flex:0 0 auto;margin:0 auto}',
    '.lbx-info{padding:14px 16px 18px;overflow-y:auto;scrollbar-width:none}',
    '.lbx-info::-webkit-scrollbar{display:none}',
    '.lbx-date{display:flex;align-items:center;font-size:11px;color:var(--t3);margin-bottom:8px}',
    '.lbx-date .ed{margin-left:auto;cursor:pointer}',
    '.lbx-date .pen{margin-left:6px;cursor:pointer;opacity:.75;font-style:normal}',
    '.lbx-date .pen:active{color:var(--accent)}',
    '.lbx-fix{position:absolute;inset:0;display:none;align-items:center;justify-content:center;',
    '  background:rgba(3,6,9,.5);backdrop-filter:blur(3px);z-index:5;padding:16px}',
    '.lbx-fix.show{display:flex}',
    '.lbx-fix .fx{width:100%;background:var(--panel2);border-radius:14px;padding:16px 14px 12px;',
    '  border:1px solid rgba(255,255,255,.1)}',
    '.lbx-fix .fh{font-size:14px;font-weight:600;margin-bottom:12px}',
    '.lbx-fix label{display:flex;align-items:center;gap:10px;margin-bottom:9px}',
    '.lbx-fix label span{flex:0 0 34px;font-size:12px;color:var(--t3)}',
    '.lbx-fix input{flex:1;min-width:0;height:32px;border-radius:8px;border:1px solid #232C39;',
    '  background:#0F141B;color:#E9EEF6;font-size:12px;padding:0 9px;font-family:inherit;outline:none}',
    '.lbx-fix input:focus{border-color:rgba(61,220,151,.45)}',
    '.lbx-fix .fb{display:flex;gap:8px;margin-top:12px}',
    '.lbx-fix .fb button{flex:1;height:34px;border-radius:9px;font-family:inherit;font-size:12px;',
    '  cursor:pointer;border:1px solid #232C39;background:transparent;color:#A8B3C2}',
    '.lbx-fix .fb .ok{background:#3DDC97;border-color:#3DDC97;color:#04170F;font-weight:600}',
    '.lbx-date .ed:active{color:var(--accent)}',
    '.lbx-note{position:relative;border-radius:10px;padding:11px 12px;font-size:11.5px;line-height:1.8;',
    '  background:rgba(217,196,138,.09);border:1px solid rgba(217,196,138,.24);color:#C9B98F;',
    '  margin-bottom:12px;max-height:26vh;overflow-y:auto;scrollbar-width:none}',
    '.lbx-note::-webkit-scrollbar{display:none}',
    '.lbx-note:focus{outline:none;background:rgba(217,196,138,.16);color:#EFE3C6}',
    '.lbx-note.np{color:#8C7A55;font-style:italic;cursor:text}',
    '.lbx-note.np::after{content:"\u270E";position:absolute;right:9px;top:7px;font-size:11px;',
    '  font-style:normal;opacity:.55}',
    '.lbx-acts{display:flex;gap:8px}',
    '.lbx-acts button{flex:1;height:36px;border-radius:10px;font-family:inherit;font-size:11.5px;',
    '  cursor:pointer;border:1px solid var(--line);background:transparent;color:var(--t2)}',
    '.lbx-acts button.on{color:var(--accent);border-color:rgba(61,220,151,.5);',
    '  background:rgba(61,220,151,.08)}',
    '.lbx-acts button.del{flex:0 0 auto;padding:0 14px;border-color:rgba(255,122,138,.45);',
    '  background:rgba(255,122,138,.1);color:#FF7A8A}',
    '.lbx-acts button.warn{background:#FF5C6C;border-color:#FF5C6C;color:#fff;font-weight:700}',

    '.lbx-confirm{position:absolute;inset:0;z-index:270;display:none;align-items:center;',
    '  justify-content:center;padding:28px;background:rgba(3,6,9,.78);backdrop-filter:blur(5px)}',
    '.lbx-confirm.show{display:flex}',
    '.lbx-cf{width:100%;max-width:270px;background:var(--panel2);border-radius:16px;',
    '  padding:20px 18px 14px;border:1px solid rgba(255,255,255,.1);text-align:center}',
    '.lbx-cf b{display:block;font-size:14px;font-weight:600;margin-bottom:8px}',
    '.lbx-cf p{font-size:11px;line-height:1.7;color:var(--t3);margin:0 0 16px}',
    '.lbx-cf .row{display:flex;gap:9px}',
    '.lbx-cf button{flex:1;height:36px;border-radius:10px;font-family:inherit;font-size:12px;',
    '  cursor:pointer;border:1px solid var(--line);background:transparent;color:var(--t2)}',
    '.lbx-cf .danger{background:rgba(255,122,138,.14);border-color:rgba(255,122,138,.5);',
    '  color:#FF7A8A;font-weight:600}',

    '.lbx-toast{position:absolute;left:50%;bottom:88px;transform:translate(-50%,8px);z-index:260;',
    '  background:rgba(20,26,35,.97);border:1px solid #232C39;color:#E9EEF6;font-size:11.5px;',
    '  padding:9px 14px;border-radius:10px;opacity:0;transition:.22s;white-space:nowrap;',
    '  box-shadow:0 12px 30px -12px #000;pointer-events:none}',
    '.lbx-toast.show{opacity:1;transform:translate(-50%,0)}',
    'html.light .lbx-card{background:#fff;border-color:#DCE3ED}',
    'html.light .lbx-note{background:rgba(190,160,80,.14);border-color:rgba(150,120,40,.3);color:#6B5620}'
  ].join('\n');

  var el = null, cur = null, noteTimer = null;
  var cfEl = null;
  var cssReady = false;
  function ensureCSS(){
    if(cssReady) return;
    cssReady = true;
    var st = document.createElement('style');
    st.textContent = CSS;
    document.head.appendChild(st);
  }

  var cfOpts = null;
  function confirm(opts){
    cfOpts = opts || {};
    ensureCSS();
    var host = document.querySelector('.device') || document.body;
    if(!cfEl) build();
    byId('lbxCfTitle').textContent = cfOpts.title || '确认操作？';
    byId('lbxCfDesc').innerHTML = cfOpts.desc || '';
    byId('lbxCfOk').textContent = cfOpts.okText || '确定';
    byId('lbxConfirm').classList.add('show');
  }

  function toast(msg){
    ensureCSS();
    var host = document.querySelector('.device') || document.body;
    var t = document.createElement('div');
    t.className = 'lbx-toast';
    t.textContent = msg;
    host.appendChild(t);
    setTimeout(function(){ t.classList.add('show'); }, 10);
    setTimeout(function(){
      t.classList.remove('show');
      setTimeout(function(){ if(t.parentNode) t.parentNode.removeChild(t); }, 260);
    }, 1700);
  }

  function build(){
    if(el) return;
    ensureCSS();

    el = document.createElement('div');
    el.className = 'lbx';
    el.innerHTML =
      '<div class="lbx-card">' +
        '<div class="lbx-img" id="lbxImg"></div>' +
        '<div class="lbx-info">' +
          '<div class="lbx-date"><span id="lbxDate">—</span>' +
            '<span class="ed" id="lbxEdit">修改</span></div>' +
          '<div class="lbx-note" id="lbxNote"></div>' +
          '<div class="lbx-acts">' +
            '<button id="lbxCover">设为封面</button>' +
            '<button id="lbxFeat">加入精选</button>' +
          '</div>' +
          '<div class="lbx-acts" style="margin-top:8px">' +
            '<button class="del" id="lbxDel">删除这张</button>' +
            '<button id="lbxClose">关闭</button>' +
          '</div>' +
        '</div>' +
        '<div class="lbx-fix" id="lbxFix">' +
          '<div class="fx">' +
            '<div class="fh">修正照片信息</div>' +
            '<label><span>日期</span><input id="fxDate" type="date"></label>' +
            '<label><span>地点</span><input id="fxPlace" type="text" placeholder="例如 双廊"></label>' +
            '<div class="fb"><button id="fxCancel">取消</button><button class="ok" id="fxOk">保存</button></div>' +
          '</div>' +
        '</div>' +
      '</div>';
    var hostEl = document.querySelector('.device') || document.body;
    hostEl.appendChild(el);

    /* 确认弹窗独立成层：不打开大图也要能用 */
    cfEl = document.createElement('div');
    cfEl.className = 'lbx-confirm';
    cfEl.id = 'lbxConfirm';
    cfEl.innerHTML =
      '<div class="lbx-cf">' +
        '<b id="lbxCfTitle">删除这张照片？</b>' +
        '<p id="lbxCfDesc">只从这次行程里移除<br>原图仍在系统相册</p>' +
        '<div class="row">' +
          '<button id="lbxCfCancel">取消</button>' +
          '<button class="danger" id="lbxCfOk">删除</button>' +
        '</div>' +
      '</div>';
    hostEl.appendChild(cfEl);

    el.addEventListener('click', function(e){ if(e.target === el) close(); });
    byId('lbxClose').addEventListener('click', close);
    byId('lbxEdit').addEventListener('click', openFix);
    byId('fxCancel').addEventListener('click', function(){ byId('lbxFix').classList.remove('show'); });
    byId('fxOk').addEventListener('click', saveFix);
    byId('lbxFix').addEventListener('click', function(e){
      if(e.target === byId('lbxFix')) byId('lbxFix').classList.remove('show');
    });
    var noteEl = byId('lbxNote');
    noteEl.addEventListener('focus', function(){
      if(noteEl.classList.contains('np')){
        noteEl.textContent = '';
        noteEl.classList.remove('np');
      }
    });
    noteEl.addEventListener('input', function(){
      if(noteTimer) clearTimeout(noteTimer);
      noteTimer = setTimeout(saveNote, 500);
    });
    noteEl.addEventListener('blur', function(){
      if(!noteEl.textContent.trim()){
        noteEl.textContent = PLACEHOLDER;
        noteEl.classList.add('np');
      }
      saveNote();
    });

    byId('lbxFeat').addEventListener('click', function(){
      if(!cur || !cur.feat) return;
      var on = cur.feat.toggle();
      paintFeat(on);
      toast(on ? '已加入精选' : '已取消精选');
    });

    byId('lbxCover').addEventListener('click', function(){
      if(!cur || !cur.cover) return;
      cur.cover();
      paintCover(true);
      toast('已设为行程封面');
    });

    byId('lbxDel').addEventListener('click', function(){
      if(!cur || !cur.onDelete) return;
      confirm({
        title: '删除这张照片？',
        desc: '只从这次行程里移除<br>原图仍在系统相册',
        okText: '删除',
        onOk: function(){ cur.onDelete(); close(); }
      });
    });

    byId('lbxCfCancel').addEventListener('click', function(){
      byId('lbxConfirm').classList.remove('show');
      cfOpts = null;
    });
    byId('lbxConfirm').addEventListener('click', function(e){
      if(e.target === this){ this.classList.remove('show'); cfOpts = null; }
    });
    byId('lbxCfOk').addEventListener('click', function(){
      byId('lbxConfirm').classList.remove('show');
      var o = cfOpts; cfOpts = null;
      if(o && o.onOk) o.onOk();
    });
  }

  function byId(id){ return document.getElementById(id); }

  function composeTitle(m){
    if(!m) return '';
    var parts = [m.date, m.place, m.suffix].filter(function(x){ return x; });
    return parts.join(' · ');
  }

  function paintTitle(){
    if(!cur) return;
    byId('lbxDate').textContent = cur.meta ? composeTitle(cur.meta) : (cur.title || '');
  }

  function openFix(){
    if(!cur || !cur.meta) return;
    byId('fxDate').value = cur.meta.iso || '';
    byId('fxPlace').value = cur.meta.place || '';
    byId('lbxFix').classList.add('show');
  }

  function saveFix(){
    if(!cur || !cur.meta) return;
    var iso = byId('fxDate').value;
    var place = byId('fxPlace').value.trim();
    var label = cur.meta.date;
    if(iso){
      var p = iso.split('-');
      label = parseInt(p[1], 10) + '月' + parseInt(p[2], 10) + '日';
    }
    cur.meta.iso = iso;
    cur.meta.date = label;
    cur.meta.place = place;
    if(cur.metaKey && window.setPhotoMeta){
      window.setPhotoMeta(cur.metaKey, {iso: iso, date: label, place: place});
    }
    paintTitle();
    byId('lbxFix').classList.remove('show');
    toast('已修正照片信息');
  }

  function sizeBox(ar){
    var img = byId('lbxImg'), card = el.querySelector('.lbx-card');
    var p = String(ar || '3 / 2').split('/');
    var r = parseFloat(p[0]) / parseFloat(p[1] || 1);
    var maxW = Math.min(340, window.innerWidth * 0.86);
    var maxH = window.innerHeight * 0.54;
    var w = Math.min(maxW, maxH * r);
    img.style.width = w + 'px';
    img.style.height = (w / r) + 'px';
    card.style.width = w + 'px';
  }

  function paintCover(on){
    var b = byId('lbxCover');
    b.classList.toggle('on', !!on);
    b.textContent = on ? '已是封面' : '设为封面';
  }

  function paintFeat(on){
    var f = byId('lbxFeat');
    f.classList.toggle('on', !!on);
    f.textContent = on ? '已在精选' : '加入精选';
  }

  function saveNote(){
    if(!cur || !cur.noteKey) return;
    var t = byId('lbxNote').textContent.trim();
    if(t === PLACEHOLDER) t = '';
    if(window.noteSet) window.noteSet(cur.noteKey, t, cur.sc);
  }
  var PLACEHOLDER = '给这张照片写点什么…';

  function close(){
    if(!el) return;
    saveNote();
    el.classList.remove('show');
    cur = null;
  }

  function open(o){
    build();
    cur = o;

    var img = byId('lbxImg');
    /* scene/ph 两个类名各页都有其一，合起来用兼容所有页面 */
    img.className = 'lbx-img scene ph ' + (o.sc || 'sc1');
    sizeBox(o.ar);

    var meta = null;
    if(o.meta){
      meta = {iso: o.meta.iso || '', date: o.meta.date || '', place: o.meta.place || '', suffix: o.meta.suffix || ''};
      if(o.metaKey && window.photoMeta){
        var sv = window.photoMeta(o.metaKey);
        if(sv){
          if(sv.iso) meta.iso = sv.iso;
          if(sv.date) meta.date = sv.date;
          if(sv.place !== undefined) meta.place = sv.place;
        }
      }
    }
    cur.meta = meta;
    cur.metaKey = o.metaKey || '';
    byId('lbxEdit').style.display = meta ? '' : 'none';
    paintTitle();

    var saved = (o.noteKey && window.noteGet) ? window.noteGet(o.noteKey) : '';
    var note = byId('lbxNote');
    note.textContent = saved || o.noteDefault || PLACEHOLDER;
    note.classList.toggle('np', !saved && !o.noteDefault);
    note.setAttribute('contenteditable', 'true');

    byId('lbxCover').style.display = o.cover ? '' : 'none';
    byId('lbxFeat').style.display = o.feat ? '' : 'none';
    byId('lbxDel').style.display = o.onDelete ? '' : 'none';
    byId('lbxDel').textContent = '删除这张';
    byId('lbxDel').classList.remove('warn');

    if(o.feat) paintFeat(o.feat.on);
    if(o.cover) paintCover(!!o.isCover);
    el.classList.add('show');
  }

  window.Lightbox = {
    confirm: confirm, open: open, close: close, toast: toast };
})();
