"use strict";

const labels = {
  waiting: "等待确认",
  running: "运行中",
  failed: "失败",
  completed: "已完成",
  interrupted: "已中断",
  idle: "空闲",
};

const state = {
  snapshot: null,
  query: "",
  status: "all",
  project: "all",
  connected: false,
};

const elements = {
  connection: document.querySelector("#connection"),
  connectionLabel: document.querySelector("#connection-label"),
  freshness: document.querySelector("#freshness"),
  search: document.querySelector("#search"),
  status: document.querySelector("#status-filter"),
  project: document.querySelector("#project-filter"),
  priorityList: document.querySelector("#priority-list"),
  recentList: document.querySelector("#recent-list"),
  otherList: document.querySelector("#other-list"),
  otherSection: document.querySelector("#other-section"),
  priorityCount: document.querySelector("#priority-count"),
  recentCount: document.querySelector("#recent-count"),
  otherCount: document.querySelector("#other-count"),
  empty: document.querySelector("#empty-state"),
};

function formatDuration(milliseconds) {
  const total = Math.max(0, Math.floor((milliseconds || 0) / 1000));
  const hours = Math.floor(total / 3600);
  const minutes = Math.floor((total % 3600) / 60);
  const seconds = total % 60;
  if (hours) return `${hours}h ${String(minutes).padStart(2, "0")}m`;
  if (minutes) return `${minutes}m ${String(seconds).padStart(2, "0")}s`;
  return `${seconds}s`;
}

function effectiveDuration(task) {
  if (["running", "waiting"].includes(task.status) && task.turn_started_at) {
    return Date.now() - task.turn_started_at;
  }
  return task.duration_ms || 0;
}

function relativeTime(timestamp) {
  const seconds = Math.max(0, Math.floor((Date.now() - timestamp) / 1000));
  if (seconds < 8) return "刚刚";
  if (seconds < 60) return `${seconds} 秒前`;
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return `${minutes} 分钟前`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours} 小时前`;
  return `${Math.floor(hours / 24)} 天前`;
}

function text(tag, className, value) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  node.textContent = value;
  return node;
}

function taskCard(task) {
  const card = document.createElement("a");
  card.className = "task-card";
  card.dataset.status = task.status;
  card.href = task.deep_link;
  card.setAttribute("aria-label", `在 Codex 中打开 ${task.title}`);

  const identity = document.createElement("div");
  const titleRow = document.createElement("div");
  titleRow.className = "task-title-row";
  titleRow.append(text("span", "status-pip", ""), text("h3", "task-title", task.title));
  identity.append(titleRow, text("p", "task-project", `${task.project} · ${task.path_hint}`));

  const progress = document.createElement("div");
  progress.append(
    text("p", "task-step", task.current_step || labels[task.status]),
    text("p", "task-progress", task.latest_progress || labels[task.status]),
  );

  const metrics = document.createElement("div");
  metrics.className = "task-metrics";
  const elapsed = document.createElement("div");
  elapsed.className = "metric";
  elapsed.append(text("span", "", "用时"), text("strong", "elapsed", formatDuration(effectiveDuration(task))));
  elapsed.dataset.startedAt = task.turn_started_at || "";
  elapsed.dataset.duration = task.duration_ms || 0;
  elapsed.dataset.live = ["running", "waiting"].includes(task.status) ? "true" : "false";
  const files = document.createElement("div");
  files.className = "metric";
  files.append(text("span", "", "文件"), text("strong", "", String(task.changed_file_count || 0)));
  metrics.append(elapsed, files, text("span", "open-arrow", "↗"));

  card.append(identity, progress, metrics);
  return card;
}

function matches(task) {
  const haystack = `${task.title} ${task.project} ${task.path_hint} ${task.current_step}`.toLocaleLowerCase();
  return (!state.query || haystack.includes(state.query))
    && (state.status === "all" || task.status === state.status)
    && (state.project === "all" || task.project === state.project);
}

function updateProjects(tasks) {
  const selected = state.project;
  const projects = [...new Set(tasks.map((task) => task.project))].sort((a, b) => a.localeCompare(b, "zh-CN"));
  elements.project.replaceChildren(new Option("全部项目", "all"));
  projects.forEach((project) => elements.project.add(new Option(project, project)));
  if (projects.includes(selected)) elements.project.value = selected;
  else state.project = "all";
}

function render() {
  if (!state.snapshot) return;
  const tasks = state.snapshot.tasks || [];
  updateProjects(tasks);
  ["waiting", "running", "failed", "completed"].forEach((status) => {
    const count = state.snapshot.summary?.[status] || 0;
    document.querySelector(`#count-${status}`).textContent = String(count);
  });

  const filtered = tasks.filter(matches);
  const priority = filtered.filter((task) => ["waiting", "running", "failed"].includes(task.status));
  const recent = filtered.filter((task) => task.status === "completed");
  const other = filtered.filter((task) => ["interrupted", "idle"].includes(task.status));
  elements.priorityList.replaceChildren(...priority.map(taskCard));
  elements.recentList.replaceChildren(...recent.map(taskCard));
  elements.otherList.replaceChildren(...other.map(taskCard));
  elements.priorityCount.textContent = `${priority.length} 个任务`;
  elements.recentCount.textContent = `${recent.length} 个任务`;
  elements.otherCount.textContent = `${other.length} 个任务 · 点击${elements.otherSection.open ? "收起" : "展开"}`;
  document.querySelector(".task-section").hidden = priority.length === 0;
  document.querySelector(".task-section.recent").hidden = recent.length === 0;
  elements.otherSection.hidden = other.length === 0;
  if (["idle", "interrupted"].includes(state.status)) elements.otherSection.open = true;
  elements.empty.hidden = filtered.length !== 0;
  updateFreshness();
}

function updateFreshness() {
  if (!state.snapshot) return;
  const stale = state.snapshot.health?.stale;
  elements.connection.classList.toggle("online", state.connected && !stale);
  elements.connection.classList.toggle("stale", !state.connected || stale);
  elements.connectionLabel.textContent = stale ? "数据已延迟" : state.connected ? "实时连接" : "正在重连";
  elements.freshness.textContent = `更新于 ${relativeTime(state.snapshot.generated_at)}`;
  document.querySelectorAll(".metric[data-live='true']").forEach((metric) => {
    const start = Number(metric.dataset.startedAt);
    const fallback = Number(metric.dataset.duration);
    metric.querySelector(".elapsed").textContent = formatDuration(start ? Date.now() - start : fallback);
  });
}

function acceptSnapshot(snapshot) {
  state.snapshot = snapshot;
  state.connected = true;
  render();
}

function connect() {
  const source = new EventSource("/events");
  source.addEventListener("snapshot", (event) => {
    try { acceptSnapshot(JSON.parse(event.data)); } catch (_error) { state.connected = false; }
  });
  source.onopen = () => { state.connected = true; updateFreshness(); };
  source.onerror = () => { state.connected = false; updateFreshness(); };
}

elements.search.addEventListener("input", () => { state.query = elements.search.value.trim().toLocaleLowerCase(); render(); });
elements.status.addEventListener("change", () => { state.status = elements.status.value; render(); });
elements.project.addEventListener("change", () => { state.project = elements.project.value; render(); });
document.querySelectorAll("[data-status-filter]").forEach((button) => {
  button.addEventListener("click", () => {
    const requested = button.dataset.statusFilter;
    state.status = state.status === requested ? "all" : requested;
    elements.status.value = state.status;
    render();
  });
});
elements.otherSection.addEventListener("toggle", () => {
  if (state.snapshot) {
    const other = state.snapshot.tasks.filter(matches).filter((task) => ["interrupted", "idle"].includes(task.status));
    elements.otherCount.textContent = `${other.length} 个任务 · 点击${elements.otherSection.open ? "收起" : "展开"}`;
  }
});

fetch("/api/snapshot").then((response) => response.json()).then(acceptSnapshot).catch(() => {});
connect();
setInterval(updateFreshness, 1000);
