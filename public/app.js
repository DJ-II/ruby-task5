(() => {
  const $ = id => document.getElementById(id);
  const CONFIG = JSON.parse(document.getElementById('region-config').textContent);
  const DICTIONARIES = JSON.parse(document.getElementById('ui-translations').textContent);
  const uiLocale = () => document.getElementById('region').value;
  function t(key, data = {}) {
    const fallback = DICTIONARIES[CONFIG.default] || {};
    const value = (DICTIONARIES[uiLocale()] || fallback)[key] ?? fallback[key] ?? key;
    return value.replace(/\{(\w+)\}/g, (match, name) => String(data[name] ?? match));
  }
  function translatePage() {
    document.documentElement.lang = CONFIG.regions.find(item => item.code === uiLocale())?.html_lang || uiLocale().split('-')[0];
    document.querySelectorAll('[data-i18n]').forEach(element => { element.textContent = t(element.dataset.i18n); });
    document.querySelectorAll('[data-i18n-aria]').forEach(element => { element.setAttribute('aria-label', t(element.dataset.i18nAria)); });
    document.querySelectorAll('[data-i18n-title]').forEach(element => { element.title = t(element.dataset.i18nTitle); });
    document.title = t('page_title');
    if (el.mediaStatus?.dataset.local !== undefined) el.mediaStatus.textContent = t('media_count', {local: el.mediaStatus.dataset.local, total: el.mediaStatus.dataset.total});
  }
  window.MovieGeneratorTranslate = t;

  const el = {
    region: $('region'), seed: $('seed'), likes: $('likes'), reviews: $('reviews'),
    likesLabel: $('likes-label'), reviewsLabel: $('reviews-label'), likesNumber: $('likes-number'), reviewsNumber: $('reviews-number'), feedback: $('feedback'),
    gallery: $('gallery-view'), sentinel: $('gallery-sentinel'), table: $('table-view'),
    tbody: $('movie-tbody'), galleryTab: $('gallery-tab'), tableTab: $('table-tab'),
    catalogStatus: $('catalog-status'), currentPage: $('current-page'), pageSummary: $('page-summary'),
    prev: $('prev-page'), next: $('next-page'), modal: $('detail-modal'),
    modalBody: $('detail-content'), shuffle: $('shuffle-seed'), mediaStatus: $('media-status'),
    export: $('export-trailers'), exportProgress: $('export-progress')
  };
  const state = { region: el.region.value, seed: document.body.dataset.initialSeed, likes: 0.5,
    reviews: 2, view: 'gallery', galleryPage: 0, tablePage: 1, epoch: 0,
    galleryLoading: false, galleryError: false, tableLoading: false, details: new Map(),
    galleryController: null, tableController: null, player: null, expanded: null };

  function escapeHtml(value) {
    return String(value ?? '').replace(/[&<>"']/g, char => ({'&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'}[char]));
  }

  function query(extra = {}) {
    return new URLSearchParams({ region: state.region, seed: state.seed, likes: String(state.likes),
      reviews: String(state.reviews), ...extra }).toString();
  }

  async function request(path, signal) {
    const response = await fetch(path, { signal, headers: { Accept: 'application/json' } });
    const json = await response.json();
    if (!response.ok) throw new Error(json.error || 'Request failed.');
    return json;
  }

  function status(message, error = false) {
    el.feedback.textContent = message;
    el.feedback.classList.toggle('is-error', error);
  }

  function buildPoster(movie, target) {
    target.style.backgroundImage = `linear-gradient(165deg, transparent 35%, ${movie.accent}15), url("${movie.poster}")`;
    target.style.backgroundColor = movie.accent;
  }

  function seriesMarkup(movie) {
    if (movie.format !== 'series') return '';
    const seasons = movie.seasons || [];
    return `<section class="series-panel"><h4 class="modal-reviews-title">${t('seasons')}</h4>${seasons.map(season => `<details class="season-item"><summary>${t('season_number', {number: season.number})} · ${season.year} · ${t('episodes_count', {count: season.episodes.length})}</summary><div class="episode-list">${season.episodes.map(episode => `<div class="episode-row"><span>${t('episode_number', {number: episode.number})} · ${escapeHtml(episode.title)}</span><small>${t('episode_duration', {duration:episode.duration_minutes})}</small></div>`).join('')}</div></details>`).join('')}</section>`;
  }

  function formatLabel(movie) {
    return movie.format === 'series' ? `${t('series')} · ${t('format_details', {count:movie.season_count})}` : t('film');
  }

  function card(movie) {
    const node = $('movie-card-template').content.firstElementChild.cloneNode(true);
    const trigger = node.querySelector('.card-poster');
    trigger.setAttribute('aria-label', t('open_details', {title: movie.title}));
    buildPoster(movie, node.querySelector('.poster-image'));
    node.querySelector('.poster-index').textContent = String(movie.index).padStart(4, '0');
    node.querySelector('.poster-genre').textContent = movie.genre;
    node.querySelector('.poster-title').textContent = movie.title;
    node.querySelector('.poster-year').textContent = `${movie.year}  /  ${movie.duration_minutes} MIN`;
    node.querySelector('.card-title').textContent = movie.title;
    node.querySelector('.card-subtitle').textContent = `${formatLabel(movie)} · ${movie.year} · ${movie.actors[0]}`;
    node.querySelector('.card-social').textContent = t('view_details');
    trigger.addEventListener('click', () => openDetails(movie.index));
    return node;
  }

  async function loadGallery() {
    if (state.view !== 'gallery' || state.galleryLoading || state.galleryError) return;
    state.galleryLoading = true;
    el.sentinel.classList.add('loading');
    el.sentinel.lastElementChild.textContent = t('generating_stories');
    const epoch = state.epoch;
    const page = state.galleryPage + 1;
    const controller = new AbortController();
    state.galleryController = controller;
    try {
      const result = await request(`/api/movies?${query({ page: String(page), size: '12' })}`, controller.signal);
      if (epoch !== state.epoch) return;
      const fragment = document.createDocumentFragment();
      result.movies.forEach(movie => fragment.append(card(movie)));
      el.gallery.append(fragment);
      state.galleryPage = page;
      el.catalogStatus.textContent = t('movies_generated_meta', {count: page * 12});
      status(t('movies_generated', {count: page * 12}));
      el.sentinel.lastElementChild.textContent = t('scroll_more');
    } catch (error) {
      if (error.name === 'AbortError' || epoch !== state.epoch) return;
      state.galleryError = true;
      status(error.message, true);
      el.sentinel.innerHTML = '';
      const retry = document.createElement('button');
      retry.type = 'button'; retry.className = 'page-btn'; retry.textContent = t('retry');
      retry.addEventListener('click', () => { state.galleryError = false; loadGallery(); });
      el.sentinel.append(retry);
    } finally {
      if (epoch === state.epoch) {
        state.galleryLoading = false;
        el.sentinel.classList.remove('loading');
        if (state.view === 'gallery' && !state.galleryError && el.gallery.children.length < 12) loadGallery();
      }
    }
  }

  function renderTable(movies) {
    el.tbody.replaceChildren();
    for (const movie of movies) {
      const tr = document.createElement('tr');
      tr.className = 'movie-row';
      tr.tabIndex = 0;
      tr.setAttribute('aria-label', t('expand_details', {title: movie.title}));
      tr.innerHTML = `<td class="cell-index">${movie.index}</td><td class="cell-title">${escapeHtml(movie.title)}<span class="format-pill">${escapeHtml(formatLabel(movie))}</span></td><td>${movie.year}</td><td>${escapeHtml(movie.genre)}</td><td class="cell-cast" title="${escapeHtml(movie.actors.join(', '))}">${escapeHtml(movie.actors.join(', '))}</td><td class="cell-expander">+</td>`;
      const extra = document.createElement('tr');
      extra.className = 'table-detail'; extra.hidden = true;
      const cell = document.createElement('td');
      cell.colSpan = 6;
      extra.append(cell);
      const toggle = async () => {
        const wasOpen = !extra.hidden;
        [...el.tbody.querySelectorAll('.table-detail')].forEach(row => row.hidden = true);
        el.tbody.querySelectorAll('.cell-expander').forEach(item => item.textContent = '+');
        stopTrailer();
        if (wasOpen) return;
        extra.hidden = false; tr.querySelector('.cell-expander').textContent = '−';
        cell.innerHTML = `<div class="expanded-inner"><span>${t('loading_details')}</span></div>`;
        try {
          const detail = await getDetails(movie.index);
          if (extra.hidden) return;
          cell.innerHTML = `<div class="expanded-inner"><div><p class="modal-label">${t('movie_index', { index: movie.index })}</p><h3 class="modal-title">${escapeHtml(detail.title)}</h3><p class="modal-meta">${detail.year} · ${escapeHtml(detail.genre)} · ${detail.duration_minutes} min</p><p class="modal-tagline">${escapeHtml(detail.tagline)}</p><p class="modal-cast">${t('cast_label')} ${escapeHtml(detail.actors.join(' · '))}</p><p class="modal-cast">♥ ${detail.likes} ${t('likes_label')} · ${detail.review_count} ${t('reviews_label')}</p><h4 class="modal-reviews-title">${t('audience_reviews')}</h4>${reviewMarkup(detail.reviews)}${seriesMarkup(detail)}</div><div><div class="trailer-stage table-trailer"></div><span class="trailer-help">${t('trailer_help', { duration: detail.trailer.duration })}</span></div></div>`;
          mountTrailer(cell.querySelector('.table-trailer'), detail.trailer);
        } catch (error) { cell.textContent = error.message; }
      };
      tr.addEventListener('click', toggle);
      tr.addEventListener('keydown', event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); toggle(); } });
      el.tbody.append(tr, extra);
    }
  }

  async function loadTable() {
    const epoch = state.epoch;
    if (state.tableLoading) return;
    state.tableLoading = true;
    el.tbody.innerHTML = `<tr><td colspan="6">${t('generating_movies')}</td></tr>`;
    const controller = new AbortController();
    state.tableController = controller;
    el.prev.disabled = true; el.next.disabled = true; el.export.disabled = true;
    try {
      const data = await request(`/api/movies?${query({ page: String(state.tablePage), size: '10' })}`, controller.signal);
      if (epoch !== state.epoch || state.view !== 'table') return;
      renderTable(data.movies);
      el.catalogStatus.textContent = t('page_meta', {page: data.page, from: data.movies[0].index, to: data.movies.at(-1).index});
      el.currentPage.textContent = data.page;
      el.pageSummary.textContent = t('page_summary', {from: data.movies[0].index, to: data.movies.at(-1).index});
      el.prev.disabled = data.page === 1;
      el.next.disabled = false;
      if (!state.exportBusy) el.export.disabled = false;
      status(t('page_generated', {page: data.page}));
    } catch (error) {
      if (error.name === 'AbortError' || epoch !== state.epoch) return;
      el.tbody.innerHTML = `<tr><td colspan="6">${escapeHtml(error.message)}</td></tr>`;
      status(error.message, true);
    } finally { if (epoch === state.epoch) state.tableLoading = false; }
  }

  function resetView(scroll = true) {
    el.export.disabled = state.exportBusy || state.view !== 'table';
    state.epoch += 1;
    state.galleryController?.abort(); state.tableController?.abort();
    state.details.clear(); state.galleryPage = 0; state.tablePage = 1;
    state.galleryLoading = false; state.tableLoading = false; state.galleryError = false;
    state.expanded = null;
    el.gallery.replaceChildren();
    el.sentinel.replaceChildren();
    el.sentinel.innerHTML = `<span class="loader-dot"></span><span>${t('scroll_more')}</span>`;
    el.catalogStatus.textContent = t('generating');
    closeDetails();
    if (state.view === 'gallery') loadGallery(); else loadTable();
    if (scroll) {
      const target = document.querySelector('.catalog').getBoundingClientRect().top + window.scrollY - 18;
      if (window.scrollY > target + 70) window.scrollTo({ top: target, behavior: 'instant' });
    }
  }

  function chooseView(view) {
    if (state.view === view) return;
    state.view = view;
    el.gallery.hidden = view !== 'gallery';
    el.sentinel.hidden = view !== 'gallery';
    el.table.hidden = view !== 'table';
    el.galleryTab.classList.toggle('active', view === 'gallery');
    el.tableTab.classList.toggle('active', view === 'table');
    el.galleryTab.setAttribute('aria-pressed', view === 'gallery');
    el.tableTab.setAttribute('aria-pressed', view === 'table');
    resetView(false);
  }

  function reviewMarkup(reviews) {
    if (!reviews || reviews.length === 0) return `<p class="review-empty">${t('no_reviews')}</p>`;
    return `<div class="review-items">${reviews.map(review => `<div class="review"><span class="review-author">${escapeHtml(review.author)}</span><span class="stars">${'★'.repeat(review.rating)}${'☆'.repeat(5-review.rating)}</span><div class="review-body">${escapeHtml(review.text)}</div></div>`).join('')}</div>`;
  }

  async function getDetails(index) {
    const key = `${state.seed}/${state.region}/${state.likes}/${state.reviews}/${index}`;
    if (!state.details.has(key)) {
      state.details.set(key, request(`/api/movie/${index}?${query()}`).catch(error => { state.details.delete(key); throw error; }));
    }
    return state.details.get(key);
  }

  function stopTrailer() {
    state.player?.destroy();
    state.player = null;
  }

  function closeDetails() {
    stopTrailer();
    el.modal.hidden = true;
    document.body.classList.remove('no-scroll');
  }

  function mountTrailer(host, story) {
    stopTrailer();
    state.player = new window.MovieGeneratorTrailer(host, story);
    return state.player;
  }

  async function openDetails(index, autoPlay = false) {
    closeDetails();
    el.modal.hidden = false;
    document.body.classList.add('no-scroll');
    el.modalBody.innerHTML = `<div class="modal-bottom">${t('loading_movie')}</div>`;
    const epoch = state.epoch;
    try {
      const movie = await getDetails(index);
      if (el.modal.hidden || state.epoch !== epoch) return;
      el.modalBody.innerHTML = `<div class="modal-top"><div class="modal-label">${t('exclusive_preview', {index: movie.index})}</div><h3 class="modal-title">${escapeHtml(movie.title)}</h3><p class="modal-meta">${movie.year} · ${escapeHtml(movie.genre)} · ${movie.duration_minutes} min · ${escapeHtml(formatLabel(movie))}</p></div><div class="trailer-stage" id="trailer-stage"></div><div class="modal-bottom"><p class="modal-tagline">${escapeHtml(movie.tagline)}</p><p class="modal-cast">${t('starring')} ${escapeHtml(movie.actors.join(' · '))}</p><p class="modal-cast">♥ ${movie.likes} ${t('likes_label')} · ◉ ${movie.review_count} ${t('reviews_label')}</p><h4 class="modal-reviews-title">${t('audience_reviews')}</h4>${reviewMarkup(movie.reviews)}${seriesMarkup(movie)}</div>`;
      const player = mountTrailer($('trailer-stage'), movie.trailer);
      if (autoPlay) player.play();
    } catch (error) { if (!el.modal.hidden) el.modalBody.textContent = error.message; }
  }


  async function exportPage() {
    if (state.exportBusy || state.view !== 'table') return;
    state.exportBusy = true;
    el.export.disabled = true;
    const data = { seed: state.seed, region: state.region, page: state.tablePage, likes: state.likes, reviews: state.reviews };
    let jobId;
    try {
      el.exportProgress.textContent = t('export_started');
      const response = await fetch('/api/exports', { method:'POST', headers: {'Content-Type':'application/json','Accept':'application/json'}, body:JSON.stringify(data) });
      const started = await response.json();
      if (!response.ok) throw new Error(started.error || 'Export unavailable');
      jobId = started.id;
      while (true) {
        await new Promise(resolve => setTimeout(resolve, 1400));
        const result = await request(`/api/exports/${encodeURIComponent(jobId)}`);
        if (result.state === 'error') throw new Error(result.error || 'Export failed');
        el.exportProgress.textContent = t('export_preparing',{done:result.completed,total:result.total});
        if (result.state === 'done') {
          el.exportProgress.textContent = t('export_downloading');
          const link = document.createElement('a');
          link.href = `/api/exports/${encodeURIComponent(jobId)}/download`;
          link.download = `MovieGenerator-page-${data.page}.zip`;
          document.body.append(link);
          link.click();
          link.remove();
          break;
        }
      }
    } catch (error) {
      el.exportProgress.textContent = t('export_error', {message:error.message});
    } finally {
      state.exportBusy = false;
      el.export.disabled = state.view !== 'table' || state.tableLoading;
    }
  }

  el.export.addEventListener('click', exportPage);

  let debounce;
  function changed() {
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      state.likes = Number(el.likes.value);
      state.reviews = Number(el.reviews.value);
      state.region = el.region.value;
      if (!/^\d{1,20}$/.test(el.seed.value) || BigInt(el.seed.value) > 18446744073709551615n) {
        status(t('seed_invalid'), true); return;
      }
      state.seed = BigInt(el.seed.value).toString();
      resetView();
    }, 320);
  }

  const observer = new IntersectionObserver(entries => {
    if (entries[0].isIntersecting && state.view === 'gallery' && !state.galleryLoading && state.galleryPage > 0) loadGallery();
  }, { rootMargin: '200px' });
  observer.observe(el.sentinel);

  el.galleryTab.addEventListener('click', () => chooseView('gallery'));
  el.tableTab.addEventListener('click', () => chooseView('table'));
  el.prev.addEventListener('click', () => { if (state.tablePage > 1) { state.tablePage--; loadTable(); } });
  el.next.addEventListener('click', () => { state.tablePage++; loadTable(); });
  el.likes.addEventListener('input', () => { el.likesNumber.value = el.likes.value; el.likesLabel.textContent = el.likes.value; changed(); });
  el.likesNumber.addEventListener('input', () => { if (el.likesNumber.validity.valid && el.likesNumber.value !== '') { el.likes.value = el.likesNumber.value; el.likesLabel.textContent = el.likesNumber.value; changed(); } });
  el.reviews.addEventListener('input', () => { el.reviewsNumber.value = el.reviews.value; el.reviewsLabel.textContent = el.reviews.value; changed(); });
  el.reviewsNumber.addEventListener('input', () => { if (el.reviewsNumber.validity.valid && el.reviewsNumber.value !== '') { el.reviews.value = el.reviewsNumber.value; el.reviewsLabel.textContent = el.reviewsNumber.value; changed(); } });
  el.region.addEventListener('change', () => { translatePage(); changed(); });
  el.seed.addEventListener('input', changed);
  el.shuffle.addEventListener('click', async () => {
    try { const config = await request('/api/config'); el.seed.value = config.random_seed; changed(); }
    catch (error) { status(error.message, true); }
  });
  $('close-detail').addEventListener('click', closeDetails);
  el.modal.addEventListener('click', event => { if (event.target === el.modal) closeDetails(); });
  document.addEventListener('keydown', event => { if (event.key === 'Escape') closeDetails(); });
  window.addEventListener('pagehide', stopTrailer);
  translatePage();
  request('/api/media-status').then(info => {
    el.mediaStatus.dataset.local = info.local;
    el.mediaStatus.dataset.total = info.total;
    el.mediaStatus.textContent = t('media_count', {local: info.local, total: info.total});
    if (info.local === 0) el.mediaStatus.title = t('media_missing');
  }).catch(() => {});
  loadGallery();
})();
