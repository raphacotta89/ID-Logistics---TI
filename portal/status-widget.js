/* ============================================================
 * status-widget.js  -  v1.0
 * Central de Impressoras - TI ID Logistics
 *
 * Acrescenta em cada cartao do portal:
 *   - bolinha de status (verde / amarelo / vermelho / cinza)
 *   - barra de nivel de cada suprimento
 *   - mensagem de erro (papel, atolamento, tampa aberta)
 *
 * Nao consulta impressora alguma. O navegador nao fala SNMP.
 * Le window.IDL_STATUS, gerado pelo Coleta-Status.ps1.
 * Carregue depois de status.js e do script principal.
 * ============================================================ */
(function () {
  "use strict";

  var CSS = [
    ".st-sel{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:700;",
    "        padding:3px 9px;border-radius:20px;white-space:nowrap;border:1px solid}",
    ".st-pt{width:8px;height:8px;border-radius:50%;flex:0 0 8px}",
    ".st-ok{color:#0f7a33;border-color:#9ad9b2;background:#e8f7ee}",
    ".st-ok .st-pt{background:#12a04a}",
    ".st-al{color:#8a5a00;border-color:#f0d493;background:#fff7e3}",
    ".st-al .st-pt{background:#e8a317}",
    ".st-er{color:#a01c1c;border-color:#f0b5b5;background:#fdecec}",
    ".st-er .st-pt{background:#d92d20}",
    ".st-nd{color:#64748b;border-color:#d9dee7;background:#eef1f6}",
    ".st-nd .st-pt{background:#94a3b8}",
    "@keyframes st-pulsa{0%,100%{opacity:1}50%{opacity:.35}}",
    ".st-er .st-pt,.st-al .st-pt{animation:st-pulsa 2s ease-in-out infinite}",
    ".st-bloco{margin-top:2px;padding-top:10px;border-top:1px solid var(--border)}",
    ".st-tit{font-size:10px;font-weight:700;letter-spacing:1px;text-transform:uppercase;",
    "        color:var(--text-dim);margin-bottom:6px}",
    ".st-lin{display:flex;align-items:center;gap:8px;margin:4px 0;font-size:11.5px}",
    ".st-nome{flex:0 0 42%;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;color:var(--text-dim)}",
    ".st-bar{flex:1;height:7px;border-radius:99px;background:var(--surface-2);overflow:hidden}",
    ".st-bar>i{display:block;height:100%;border-radius:99px}",
    ".st-vazia{flex:1;height:7px;border-radius:99px;",
    "          background:repeating-linear-gradient(90deg,var(--border) 0 6px,transparent 6px 11px)}",
    ".st-pct{flex:0 0 58px;text-align:right;font-weight:700;font-variant-numeric:tabular-nums}",
    ".st-selo{display:inline-block;padding:1px 7px;border-radius:99px;font-size:10px;font-weight:700}",
    ".st-selo.bom{background:#e8f7ee;color:#0f7a33}",
    ".st-selo.ruim{background:#fdecec;color:#a01c1c}",
    ".st-erros{margin-top:7px;font-size:11.5px;font-weight:600;color:#c62828}",
    ".st-idade{margin-top:6px;font-size:10px;color:var(--text-dim)}",
    ".st-idade.velho{color:#b54708;font-weight:700}"
  ].join("\n");

  function injetaCss() {
    if (document.getElementById("st-css")) return;
    var s = document.createElement("style");
    s.id = "st-css";
    s.textContent = CSS;
    document.head.appendChild(s);
  }

  var ROTULO = { ok: "Online", alerta: "Atencao", erro: "Com problema", offline: "Offline" };
  var CLASSE = { ok: "st-ok", alerta: "st-al", erro: "st-er", offline: "st-er" };

  function esc(t) {
    return String(t == null ? "" : t).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }

  function cor(p) { return p <= 10 ? "#d92d20" : (p <= 25 ? "#e8a317" : "#12a04a"); }

  function linha(s) {
    var ini = '<div class="st-lin"><span class="st-nome" title="' + esc(s.nome) + '">' + esc(s.nome) + "</span>";
    if (s.pct === null || s.pct === undefined) {
      var trocar = (s.bruto === 0);
      return ini + '<span class="st-vazia"></span><span class="st-pct"><span class="st-selo ' +
             (trocar ? "ruim" : "bom") + '">' + (trocar ? "TROCAR" : "OK") + "</span></span></div>";
    }
    return ini + '<span class="st-bar"><i style="width:' + s.pct + "%;background:" + cor(s.pct) +
           '"></i></span><span class="st-pct">' + s.pct + "%</span></div>";
  }

  function bloco(p, idade) {
    var st = p.status || "offline";
    var h = '<div class="st-bloco">';
    if (p.erros && p.erros.length) {
      h += '<div class="st-erros">&#9888; ' + p.erros.map(esc).join(" &middot; ") + "</div>";
    }
    if (p.suprimentos && p.suprimentos.length) {
      h += '<div class="st-tit">Suprimentos</div>' + p.suprimentos.map(linha).join("");
    }
    var velho = idade > 30;
    h += '<div class="st-idade' + (velho ? " velho" : "") + '">atualizado ha ' +
         (idade < 1 ? "menos de 1 min" : idade + " min") +
         (velho ? " - pode estar desatualizado" : "") + "</div></div>";
    return h;
  }

  function selo(p) {
    var st = p.status || "offline";
    return '<span class="st-sel ' + CLASSE[st] + '" title="' + esc(p.statusTexto || "") + '">' +
           '<span class="st-pt"></span>' + (ROTULO[st] || "Sem dados") + "</span>";
  }

  function aplica() {
    var d = window.IDL_STATUS;
    if (!d || !d.impressoras) return;
    injetaCss();

    var g = new Date(String(d.geradoIso || d.gerado || "").replace(" ", "T"));
    var idade = isNaN(g) ? 999 : Math.max(0, Math.round((Date.now() - g.getTime()) / 60000));

    var porIp = {};
    d.impressoras.forEach(function (p) { porIp[p.ip] = p; });

    var cards = document.querySelectorAll(".card");
    for (var i = 0; i < cards.length; i++) {
      var c = cards[i];
      if (c.querySelector(".st-bloco") || c.querySelector(".st-sel")) continue;

      var dd = c.querySelectorAll(".meta dd");
      var ip = dd.length ? dd[0].textContent.trim() : "";
      var p = porIp[ip];
      if (!p) continue;

      var cabeca = c.querySelector(".card-head");
      if (cabeca) {
        var span = document.createElement("span");
        span.innerHTML = selo(p);
        cabeca.appendChild(span.firstChild);
      }
      var acoes = c.querySelector(".actions");
      var div = document.createElement("div");
      div.innerHTML = bloco(p, idade);
      if (acoes) c.insertBefore(div.firstChild, acoes);
      else c.appendChild(div.firstChild);
    }
  }

  function iniciar() {
    aplica();
    var lista = document.getElementById("lista");
    if (lista && window.MutationObserver) {
      // o portal reconstroi a lista a cada busca ou filtro
      new MutationObserver(function () { aplica(); }).observe(lista, { childList: true, subtree: true });
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", iniciar);
  else iniciar();

  window.IDLStatusWidget = { aplicar: aplica };
})();
