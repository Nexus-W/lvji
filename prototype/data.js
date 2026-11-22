/* 全局唯一数据源。所有页面都从这里取，不再各自硬编码。
   新增一次行程 = 往 TRIPS 里加一条，其它页面自动跟着变。 */
(function(){
  'use strict';

  var TRIPS = [
    {
      id: 'yn',
      geo: {city: '大理', province: '云南', country: '中国', lat: 25.61, lng: 100.27},
      name: '云南 · 大理丽江',
      region: '云南',
      short: '大理丽江',
      range: '2026.10.02 - 10.06',
      size: '12.4 GB',
      videos: 37,
      missing: 32,
      dist: 214,
      ascent: 1240,
      body: '第一天到大理就下错了站，拖着箱子走了两公里。\n第二天环洱海，风大得像要把人吹下山，但那段云海是真的值。\n相机一路拍，手机一路记，回来翻的时候才发现 —— 记得最清楚的不是景点，是路上那些鸡毛蒜皮。',
      cover: ['sc4','sc2','sc1'],
      labels: [
        {t:'大理', x:246, y:782},
        {t:'洱海', x:586, y:486},
        {t:'双廊', x:690, y:438},
        {t:'沙溪', x:322, y:290},
        {t:'苍山', x:168, y:556},
        {t:'凤仪', x:726, y:726}
      ],
      weather: [
        {d:'10/02', k:'sun',   t:'24°'},
        {d:'10/03', k:'cloud', t:'21°'},
        {d:'10/04', k:'rain',  t:'17°'},
        {d:'10/05', k:'bolt',  t:'19°'},
        {d:'10/06', k:'fog',   t:'23°'}
      ],
      dates: [
        {label:'10月2日', place:'大理古城', n:168, x:272, y:742, sc:'sc4'},
        {label:'10月3日', place:'洱海东岸', n:214, x:468, y:616, sc:'sc2'},
        {label:'10月4日', place:'双廊',     n:186, x:642, y:468, sc:'sc1'},
        {label:'10月5日', place:'沙溪古镇', n:152, x:356, y:318, sc:'sc7'},
        {label:'10月6日', place:'返程 · 凤仪', n:122, x:700, y:690, sc:'sc6'}
      ]
    },

    {
      id: 'qh',
      geo: {city: '西宁', province: '青海', country: '中国', lat: 36.62, lng: 101.78},
      name: '青海 · 环湖西路',
      region: '青海',
      short: '环湖西路',
      range: '2026.07.18 - 07.24',
      size: '21.8 GB',
      videos: 61,
      missing: 118,
      dist: 486,
      ascent: 2680,
      body: '',
      cover: ['sc3','sc6','sc7'],
      labels: [
        {t:'西宁', x:286, y:566},
        {t:'日月山', x:330, y:452},
        {t:'青海湖', x:452, y:372},
        {t:'茶卡', x:596, y:286},
        {t:'刚察', x:420, y:238},
        {t:'黑马河', x:470, y:346}
      ],
      weather: [
        {d:'07/18', k:'sun',   t:'22°'},
        {d:'07/19', k:'sun',   t:'20°'},
        {d:'07/20', k:'cloud', t:'18°'},
        {d:'07/21', k:'rain',  t:'14°'},
        {d:'07/22', k:'sun',   t:'21°'},
        {d:'07/23', k:'sun',   t:'23°'},
        {d:'07/24', k:'fog',   t:'19°'}
      ],
      dates: [
        {label:'7月18日', place:'西宁',     n:210, x:300, y:520, sc:'sc3'},
        {label:'7月19日', place:'日月山',   n:190, x:330, y:460, sc:'sc6'},
        {label:'7月20日', place:'二郎剑',   n:175, x:400, y:400, sc:'sc7'},
        {label:'7月21日', place:'黑马河',   n:165, x:470, y:360, sc:'sc8'},
        {label:'7月22日', place:'茶卡',     n:160, x:560, y:300, sc:'sc6'},
        {label:'7月23日', place:'刚察',     n:152, x:430, y:250, sc:'sc3'},
        {label:'7月24日', place:'返程 · 西宁', n:152, x:320, y:560, sc:'sc2'}
      ]
    },

    {
      id: 'pt',
      geo: {city: '平潭', province: '福建', country: '中国', lat: 25.50, lng: 119.79},
      name: '福建 · 平潭',
      region: '福建',
      short: '平潭',
      range: '2026.05.01 - 05.03',
      size: '6.2 GB',
      videos: 18,
      missing: 0,
      dist: 128,
      ascent: 210,
      body: '',
      cover: ['sc5','sc8','sc1'],
      labels: [
        {t:'平潭', x:398, y:700},
        {t:'北港', x:486, y:566},
        {t:'坛南湾', x:420, y:742},
        {t:'龙凤头', x:352, y:632},
        {t:'东澳', x:500, y:664}
      ],
      weather: [
        {d:'05/01', k:'cloud', t:'26°'},
        {d:'05/02', k:'rain',  t:'23°'},
        {d:'05/03', k:'sun',   t:'28°'}
      ],
      dates: [
        {label:'5月1日', place:'龙凤头', n:150, x:380, y:640, sc:'sc5'},
        {label:'5月2日', place:'北港村', n:146, x:460, y:580, sc:'sc8'},
        {label:'5月3日', place:'坛南湾', n:140, x:430, y:690, sc:'sc1'}
      ]
    }
  ];

  /* 用户自建的行程（存本地，与内置行程一起参与列表与查询） */
  function customTrips(){
    try { return JSON.parse(localStorage.getItem('tripnest.custom') || '[]') || []; }
    catch(e){ return []; }
  }
  function allTrips(){
    return customTrips().concat(TRIPS);
  }
  function getTrip(id){
    var all = allTrips();
    for(var i = 0; i < all.length; i++){
      if(all[i].id === id) return all[i];
    }
    return TRIPS[0];
  }

  /* 新建行程：只填名称与日期，其余给默认值 */
  function createTrip(name, from, to){
    var d1 = new Date(from + 'T00:00:00');
    var d2 = new Date(to + 'T00:00:00');
    var days = Math.round((d2 - d1) / 86400000) + 1;
    var dates = [], weather = [];
    var MD = ['1月','2月','3月','4月','5月','6月','7月','8月','9月','10月','11月','12月'];
    for(var i = 0; i < days; i++){
      var d = new Date(d1.getTime() + i * 86400000);
      dates.push({
        id: 'd' + i,
        label: MD[d.getMonth()] + d.getDate() + '日',
        place: '待命名',
        n: 0,
        x: 300 + i * 26, y: 700 - i * 18
      });
      weather.push({d: 'D' + (i + 1), k: 'sun', t: '--°'});
    }
    var f = from.split('-'), t2 = to.split('-');
    var rec = {
      id: 'c' + Date.now(),
      name: name,
      range: f[0] + '.' + f[1] + '.' + f[2] + ' - ' + t2[1] + '.' + t2[2],
      dist: 0, ascent: 0, size: '0 GB', missing: 0,
      dates: dates, weather: weather, cover: ['sc1','sc2','sc3'], body: ''
    };
    var list = customTrips();
    list.unshift(rec);
    try { localStorage.setItem('tripnest.custom', JSON.stringify(list)); } catch(e){}
    return rec;
  }

  function q(name){
    var m = new RegExp('[?&]' + name + '=([^&]*)').exec(location.search || '');
    return m ? decodeURIComponent(m[1]) : '';
  }

  function photos(trip){
    var out = [], pid = 0;
    trip.dates.forEach(function(d, di){
      for(var i = 0; i < d.n; i++){
        var a = Math.random() * Math.PI * 2;
        var r = Math.pow(Math.random(), 0.65) * 62;
        out.push({
          id: 'p' + (pid++),
          day: d.label,
          x: d.x + Math.cos(a) * r,
          y: d.y + Math.sin(a) * r * 0.82,
          sc: 'sc' + (1 + ((di * 3 + i) % 8))
        });
      }
    });
    return out;
  }

  /* 天气图标 */
  var ICON = {
    sun:   '<circle cx="12" cy="12" r="4"/><path d="M12 3.5v2M12 18.5v2M3.5 12h2M18.5 12h2M6 6l1.4 1.4M16.6 16.6 18 18M18 6l-1.4 1.4M7.4 16.6 6 18"/>',
    cloud: '<circle cx="8.6" cy="8" r="2.4"/><path d="M9.6 18.4h8.1a3.1 3.1 0 0 0 .2-6.2 4.7 4.7 0 0 0-8.9-1.2 3.2 3.2 0 0 0 .6 7.4Z"/>',
    rain:  '<path d="M6.8 15.4h10.6a3.3 3.3 0 0 0 .3-6.6 5.1 5.1 0 0 0-9.7-1.3 3.5 3.5 0 0 0-1.2 7.9Z"/><path d="M9 18.4l-.9 1.7M12.4 18.4l-.9 1.7M15.8 18.4l-.9 1.7"/>',
    bolt:  '<path d="M6.8 15.4h10.6a3.3 3.3 0 0 0 .3-6.6 5.1 5.1 0 0 0-9.7-1.3 3.5 3.5 0 0 0-1.2 7.9Z"/><path d="M12.6 17.2 10.8 20h2.2l-.9 2.4"/>',
    fog:   '<path d="M6.8 15.4h10.6a3.3 3.3 0 0 0 .3-6.6 5.1 5.1 0 0 0-9.7-1.3 3.5 3.5 0 0 0-1.2 7.9Z"/><path d="M8.6 18.6h7.4M8.6 21h5.6"/>'
  };

  function iconSvg(k, size){
    return '<svg viewBox="0 0 24 24" width="' + size + '" height="' + size +
           '" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">' +
           (ICON[k] || ICON.sun) + '</svg>';
  }


  /* 备注：按「照片唯一键」存取，绝不能共用同一个容器 */
  var NOTE_KEY = 'tripnest.notes';

  function noteMap(){
    try { return JSON.parse(localStorage.getItem(NOTE_KEY) || '{}') || {}; }
    catch(e){ return {}; }
  }
  function noteGet(id){
    var m = noteMap();
    return m[id] || '';
  }
  function noteSet(id, text, sc){
    var m = noteMap();
    if(text && text.trim()){ m[id] = text.trim(); } else { delete m[id]; }
    try { localStorage.setItem(NOTE_KEY, JSON.stringify(m)); } catch(e){}
    /* 额外记下场景样式，「有备注的照片」才能重新画出来 */
    if(sc){
      var meta = {};
      try { meta = JSON.parse(localStorage.getItem(NOTE_KEY + '.meta') || '{}') || {}; } catch(e){ meta = {}; }
      if(text && text.trim()) meta[id] = sc; else delete meta[id];
      try { localStorage.setItem(NOTE_KEY + '.meta', JSON.stringify(meta)); } catch(e){}
    }
  }

  /* 某个行程里「有备注」的照片 */
  function notedOf(tripId){
    var m = noteMap(), meta = {};
    try { meta = JSON.parse(localStorage.getItem(NOTE_KEY + '.meta') || '{}') || {}; } catch(e){ meta = {}; }
    var pre = 'trip:' + tripId + ':';
    var out = [];
    for(var k in m){
      if(k.indexOf(pre) === 0 && m[k]){
        out.push({ id: k.slice(pre.length), sc: meta[k] || 'sc2' });
      }
    }
    return out;
  }


  /* 一张照片属于哪几类：封面 kc / 精选 kf / 备注 kn
     展板页与地图页共用这一份判定，避免两处规则走偏 */
  function kindMapOf(tripId, defaultCoverId){
    var map = {};
    function add(id, k){
      if(!id) return;
      var a = map[id] || (map[id] = []);
      if(a.indexOf(k) < 0) a.push(k);
    }
    var cv = coverOf(tripId);
    add(cv ? cv.id : defaultCoverId, 'kc');
    featuredOf(tripId).forEach(function(f){ add(f.id, 'kf'); });
    notedOf(tripId).forEach(function(f){ add(f.id, 'kn'); });
    return map;
  }

  window.noteGet = noteGet;
  window.noteSet = noteSet;
  window.notedOf = notedOf;


  /* 已删除的行程（只删索引，不动文件） */
  var DEL_KEY = 'tripnest.deletedTrips';

  function deletedTrips(){
    try { return JSON.parse(localStorage.getItem(DEL_KEY) || '[]') || []; }
    catch(e){ return []; }
  }
  function markTripDeleted(id){
    var d = deletedTrips();
    if(d.indexOf(id) < 0) d.push(id);
    try { localStorage.setItem(DEL_KEY, JSON.stringify(d)); } catch(e){}
  }
  function aliveTrips(){
    var d = deletedTrips();
    return allTrips().filter(function(t){ return d.indexOf(t.id) < 0; });
  }

  /* 封面 / 精选 */
  /* 封面存 {id, sc}，保留最近三次设置的历史：列表取第 1 张，卡片拼贴取前 3 张 */
  function coversOf(tripId){
    var list = [];
    try { list = JSON.parse(localStorage.getItem('tripnest.covers.' + tripId) || '[]') || []; }
    catch(e){ list = []; }
    if(!Array.isArray(list)) list = [];
    /* 兼容旧版只存一张的格式 */
    try {
      var one = JSON.parse(localStorage.getItem('tripnest.cover.' + tripId) || 'null');
      if(one && one.id){
        var has = false;
        for(var i = 0; i < list.length; i++){ if(list[i].id === one.id) has = true; }
        if(!has) list.unshift(one);
      }
    } catch(e){}
    return list;
  }

  function coverOf(tripId){
    var list = coversOf(tripId);
    return list.length ? list[0] : null;
  }

  function setCover(tripId, photo){
    try {
      if(photo){
        var list = coversOf(tripId).filter(function(x){ return x.id !== photo.id; });
        list.unshift(photo);
        list = list.slice(0, 3);
        localStorage.setItem('tripnest.covers.' + tripId, JSON.stringify(list));
        localStorage.setItem('tripnest.cover.' + tripId, JSON.stringify(photo));
      } else {
        localStorage.removeItem('tripnest.covers.' + tripId);
        localStorage.removeItem('tripnest.cover.' + tripId);
      }
    } catch(e){}
  }

  /* 精选：数组，元素同样是 {id, sc} */
  function featuredOf(tripId){
    try { return JSON.parse(localStorage.getItem('tripnest.feat.' + tripId) || '[]') || []; }
    catch(e){ return []; }
  }
  function toggleFeatured(tripId, photo){
    var a = featuredOf(tripId);
    var idx = -1;
    for(var i = 0; i < a.length; i++){ if(a[i].id === photo.id){ idx = i; break; } }
    if(idx >= 0) a.splice(idx, 1);
    else a.push({id: photo.id, sc: photo.sc, t: photo.t || ''});
    try { localStorage.setItem('tripnest.feat.' + tripId, JSON.stringify(a)); } catch(e){}
    return a;
  }
  function isFeatured(tripId, photoId){
    var a = featuredOf(tripId);
    for(var i = 0; i < a.length; i++){ if(a[i].id === photoId) return true; }
    return false;
  }


  /* 行程基本信息可被用户改写：名称 / 起止日期 */
  function tripMeta(tripId){
    try { return JSON.parse(localStorage.getItem('tripnest.meta.' + tripId) || 'null'); }
    catch(e){ return null; }
  }
  function setTripMeta(tripId, m){
    try {
      if(m) localStorage.setItem('tripnest.meta.' + tripId, JSON.stringify(m));
      else localStorage.removeItem('tripnest.meta.' + tripId);
    } catch(e){}
  }
  function tripName(t){ var m = tripMeta(t.id); return (m && m.name) || t.name; }
  function tripRange(t){ var m = tripMeta(t.id); return (m && m.range) || t.range; }
  function tripDays(t){
    var m = tripMeta(t.id);
    return (m && m.days) || t.dates.length;
  }

  window.importedOf = importedOf;
  window.addImported = addImported;
  window.customTrips = customTrips;
  window.allTrips = allTrips;
  window.createTrip = createTrip;

  /* 单张照片的「时间 / 地点」可被用户修正，按 metaKey 存 */
  function photoMeta(key){
    try {
      var m = JSON.parse(localStorage.getItem('tripnest.pmeta') || '{}') || {};
      return m[key] || null;
    } catch(e){ return null; }
  }
  function setPhotoMeta(key, val){
    try {
      var m = JSON.parse(localStorage.getItem('tripnest.pmeta') || '{}') || {};
      if(val) m[key] = val; else delete m[key];
      localStorage.setItem('tripnest.pmeta', JSON.stringify(m));
    } catch(e){}
  }

  window.nearestPlace = nearestPlace;
  window.tripMeta = tripMeta;
  window.setTripMeta = setTripMeta;
  window.photoMeta = photoMeta;
  window.setPhotoMeta = setPhotoMeta;
  window.tripName = tripName;
  window.tripRange = tripRange;
  window.tripDays = tripDays;
  window.deletedTrips = deletedTrips;
  window.markTripDeleted = markTripDeleted;
  window.aliveTrips = aliveTrips;
  window.coverOf = coverOf;
  window.coversOf = coversOf;

  /* 本次新导入的张数（挂在行程上，让列表立刻看得到增量） */
  function importedOf(tripId){
    try { return parseInt(localStorage.getItem('tripnest.imported.' + tripId) || '0', 10) || 0; }
    catch(e){ return 0; }
  }
  function addImported(tripId, n){
    try {
      localStorage.setItem('tripnest.imported.' + tripId, String(importedOf(tripId) + n));
    } catch(e){}
  }


  /* 常用地点：正式版由腾讯位置服务的搜索/逆地理编码接口返回 */
  var PLACES = [
    {n:'大理古城', lat:25.60, lng:100.16},
    {n:'洱海东岸', lat:25.75, lng:100.20},
    {n:'双廊',    lat:25.90, lng:100.26},
    {n:'喜洲',    lat:25.85, lng:100.12},
    {n:'挖色',    lat:25.65, lng:100.30},
    {n:'沙溪古镇', lat:26.15, lng:99.85}
  ];
  function nearestPlace(lat, lng){
    var best = null, bestD = 1e9;
    for(var i = 0; i < PLACES.length; i++){
      var d = Math.pow(PLACES[i].lat - lat, 2) + Math.pow(PLACES[i].lng - lng, 2);
      if(d < bestD){ bestD = d; best = PLACES[i]; }
    }
    return (best && bestD < 0.0016) ? best : null;
  }

  window.PLACES = PLACES;


  window.kindMapOf = kindMapOf;
  window.setCover = setCover;
  window.featuredOf = featuredOf;
  window.toggleFeatured = toggleFeatured;
  window.isFeatured = isFeatured;

  window.TRIPS = TRIPS;
  window.getTrip = getTrip;
  window.q = q;
  window.makePhotos = photos;
  window.iconSvg = iconSvg;
})();
