(function () {
  if (window.__ghzh) return;
  window.__ghzh = true;

  // ========== 1. 界面中文化（词典替换） ==========
  var UI_ON = localStorage.getItem('gh_zh') !== '0';

  var dict = {
    'Code': '代码', 'Issues': '议题', 'Pull requests': '拉取请求', 'Actions': '操作',
    'Projects': '项目', 'Wiki': '维基', 'Security': '安全', 'Insights': '洞察',
    'Settings': '设置', 'Discussions': '讨论', 'Packages': '软件包', 'Releases': '发行版',
    'Sign in': '登录', 'Sign up': '注册', 'Sign out': '退出登录',
    'Search or jump to...': '搜索或跳转到…', 'Search': '搜索',
    'Star': '星标', 'Starred': '已加星标', 'Unstar': '取消星标', 'Stars': '星标',
    'Fork': '复刻', 'Forks': '复刻', 'Watch': '关注', 'Unwatch': '取消关注', 'Watchers': '关注者',
    'Notifications': '通知', 'Dashboard': '仪表板', 'Home': '主页',
    'Your profile': '你的个人资料', 'Your repositories': '你的仓库', 'Your projects': '你的项目',
    'Your stars': '你的星标', 'Your gists': '你的代码片段', 'Your organizations': '你的组织',
    'Repositories': '仓库', 'Overview': '概览', 'Followers': '关注者', 'Following': '正在关注',
    'Follow': '关注', 'Unfollow': '取消关注',
    'New': '新建', 'New issue': '新建议题', 'New pull request': '新建拉取请求',
    'New repository': '新建仓库', 'Create repository': '创建仓库',
    'Open': '打开', 'Closed': '已关闭', 'Merged': '已合并', 'Draft': '草稿',
    'Comment': '评论', 'Close issue': '关闭议题', 'Reopen issue': '重新打开议题',
    'Submit new issue': '提交新议题', 'Write': '编写', 'Preview': '预览',
    'Labels': '标签', 'Milestones': '里程碑', 'Assignees': '指派人', 'Assignee': '指派人',
    'Reviewers': '审阅者', 'Linked pull requests': '关联的拉取请求',
    'Branches': '分支', 'Branch': '分支', 'Tags': '标签', 'Tag': '标签',
    'Commits': '提交', 'Commit': '提交', 'Contributors': '贡献者', 'Languages': '语言',
    'About': '关于', 'Readme': '自述文件', 'README': '自述文件', 'License': '许可证',
    'Activity': '动态', 'Custom properties': '自定义属性',
    'Clone': '克隆', 'Download ZIP': '下载 ZIP', 'Open with GitHub Desktop': '用 GitHub Desktop 打开',
    'Add file': '添加文件', 'Upload files': '上传文件', 'Create new file': '创建新文件',
    'Go to file': '转到文件', 'Raw': '原始文件', 'Copy': '复制', 'Copied!': '已复制！',
    'Blame': '追溯', 'History': '历史', 'Edit': '编辑', 'Delete': '删除',
    'Save': '保存', 'Cancel': '取消', 'Update': '更新', 'Commit changes': '提交更改',
    'Public': '公开', 'Private': '私有', 'Archived': '已归档',
    'Latest': '最新', 'Pre-release': '预发布', 'Latest commit': '最新提交',
    'Explore': '探索', 'Trending': '热门趋势', 'Marketplace': '应用市场', 'Topics': '主题',
    'Sponsor': '赞助', 'Sponsors': '赞助者', 'Help': '帮助', 'Support': '支持',
    'Pricing': '定价', 'Documentation': '文档', 'Contact': '联系', 'Terms': '条款',
    'Privacy': '隐私', 'Status': '状态',
    'Profile': '个人资料', 'Account': '账户', 'Appearance': '外观', 'Security log': '安全日志',
    'Developer settings': '开发者设置', 'Personal access tokens': '个人访问令牌',
    'Password and authentication': '密码和身份验证', 'Emails': '邮箱', 'Billing': '账单',
    'Organizations': '组织', 'Secrets and variables': '密钥和变量', 'Secrets': '密钥',
    'Variables': '变量', 'Workflows': '工作流', 'All workflows': '所有工作流',
    'Run workflow': '运行工作流', 'Re-run all jobs': '重新运行所有作业',
    'Artifacts': '构建产物', 'Summary': '摘要', 'Jobs': '作业',
    'Sort': '排序', 'Filter': '筛选', 'Newest': '最新', 'Oldest': '最早',
    'Most commented': '评论最多', 'Recently updated': '最近更新',
    'Previous': '上一页', 'Next': '下一页', 'Load more': '加载更多',
    'No results': '没有结果', 'Loading': '加载中', 'Loading...': '加载中…',
    'Sign in with a passkey': '使用通行密钥登录', 'Forgot password?': '忘记密码？',
    'Username or email address': '用户名或邮箱地址', 'Password': '密码',
    'Create account': '创建账户', 'Continue': '继续', 'Verify': '验证',
    'Dismiss': '忽略', 'Mark as read': '标为已读', 'Mark all as read': '全部标为已读',
    'Unread': '未读', 'Read': '已读', 'Saved': '已保存', 'Done': '完成',
    'Add': '添加', 'Remove': '移除', 'Create': '创建', 'Apply': '应用',
    'Show more': '显示更多', 'Show less': '显示更少', 'View all': '查看全部',
    'Pinned': '已置顶', 'Popular repositories': '热门仓库', 'Contribution settings': '贡献设置'
  };

  var SKIP = 'script,style,pre,code,textarea,input,.markdown-body,.blob-code,.react-code-text,.highlight';

  function skipNode(n) {
    var el = n.nodeType === 1 ? n : n.parentElement;
    return !el || (el.closest && el.closest(SKIP));
  }

  function zhText(n) {
    var raw = n.nodeValue;
    if (!raw) return;
    var t = raw.trim();
    if (t.length < 2 || t.length > 40) return;
    var zh = dict[t];
    if (zh && !skipNode(n)) n.nodeValue = raw.replace(t, zh);
  }

  function zhAttrs(el) {
    ['placeholder', 'aria-label', 'title'].forEach(function (a) {
      var v = el.getAttribute && el.getAttribute(a);
      if (v && dict[v.trim()]) el.setAttribute(a, dict[v.trim()]);
    });
  }

  function walk(root) {
    if (root.nodeType === 3) { zhText(root); return; }
    if (root.nodeType !== 1) return;
    if (root.closest && root.closest('script,style')) return;
    zhAttrs(root);
    var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
    var n;
    while ((n = w.nextNode())) zhText(n);
    var els = root.querySelectorAll('[placeholder],[aria-label],[title]');
    for (var i = 0; i < els.length; i++) zhAttrs(els[i]);
  }

  if (UI_ON) {
    walk(document.body);
    var queue = [];
    var scheduled = false;
    new MutationObserver(function (muts) {
      muts.forEach(function (m) {
        m.addedNodes.forEach(function (n) { queue.push(n); });
        if (m.type === 'characterData') queue.push(m.target);
      });
      if (!scheduled) {
        scheduled = true;
        requestAnimationFrame(function () {
          scheduled = false;
          var q = queue; queue = [];
          q.forEach(function (n) { try { walk(n); } catch (e) {} });
        });
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true });
  }

  // ========== 2. 页面内容翻译（调用原生翻译） ==========
  var CONTENT_SEL = [
    '.markdown-body', '.comment-body', '.js-issue-title', '[data-testid="issue-title"]',
    '[data-testid="markdown-body"]', '.f4.my-3', '[itemprop="about"]', '.commit-title',
    '.release-header', '.markdown-title', '.Box-body p'
  ].join(',');

  var LATIN = /[A-Za-z]{3,}/;
  var CJK = /[\u4e00-\u9fff]/;
  var SKIP_T = 'script,style,pre,code,textarea,kbd,.blob-code,.react-code-text,.highlight,svg';

  var translated = new Map();
  var isOn = false;
  var reqId = 0;
  var pending = {};

  function ask(texts) {
    return new Promise(function (resolve) {
      var id = ++reqId;
      pending[id] = resolve;
      window.webkit.messageHandlers.translate.postMessage({ id: id, texts: texts });
    });
  }
  window.__ghApply = function (id, arr) {
    var r = pending[id];
    if (r) { delete pending[id]; r(arr); }
  };

  function collect() {
    var nodes = [];
    var seen = new Set();
    document.querySelectorAll(CONTENT_SEL).forEach(function (root) {
      var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, null);
      var n;
      while ((n = w.nextNode())) {
        if (seen.has(n) || translated.has(n)) continue;
        var t = n.nodeValue;
        if (!t || t.trim().length < 3 || !LATIN.test(t) || CJK.test(t)) continue;
        if (n.parentElement && n.parentElement.closest(SKIP_T)) continue;
        seen.add(n);
        nodes.push(n);
      }
    });
    return nodes;
  }

  async function run() {
    var nodes = collect();
    var BATCH = 15;
    for (var i = 0; i < nodes.length; i += BATCH) {
      if (!isOn) return;
      var slice = nodes.slice(i, i + BATCH);
      var texts = slice.map(function (n) { return n.nodeValue; });
      var out = await ask(texts);
      if (!isOn) return;
      slice.forEach(function (n, k) {
        if (out[k] && out[k] !== texts[k] && n.isConnected) {
          translated.set(n, texts[k]);
          // 保留首尾空白，避免行内元素粘连
          var lead = (texts[k].match(/^\s*/) || [''])[0];
          var trail = (texts[k].match(/\s*$/) || [''])[0];
          n.nodeValue = lead + out[k].trim() + trail;
        }
      });
    }
  }

  function restore() {
    translated.forEach(function (orig, n) { if (n.isConnected) n.nodeValue = orig; });
    translated.clear();
  }

  window.__ghToggleTranslate = function () {
    isOn = !isOn;
    if (isOn) { run(); } else { restore(); }
    return isOn;
  };
})();
