(() => {
  const t = key => window.MovieGeneratorTranslate?.(key) || key;
  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[char]));

  class TrailerPlayer {
    constructor(host, story) {
      this.host = host;
      this.story = story;
      this.videos = [];
      this.timers = [];
      this.stopped = true;
      this.playing = false;
      this.audio = story.audio_url ? new Audio(story.audio_url) : null;
      if (this.audio) { this.audio.volume = 0.28; this.audio.preload = 'auto'; }
      this.mount();
    }

    mount() {
      const first = this.story.scenes[0];
      this.host.innerHTML = `<div class="trailer-poster"></div><div class="trailer-videos"></div><div class="trailer-tint"></div><div class="trailer-caption" aria-live="off"></div><div class="trailer-poster-title">${escapeHtml(this.story.title)}</div><button class="trailer-play" type="button" aria-label="${escapeHtml(t('play_trailer'))}">▶</button><div class="trailer-message" hidden></div><div class="trailer-timeline"><div class="trailer-progress"></div></div>`;
      this.poster = this.host.querySelector('.trailer-poster');
      this.poster.style.backgroundImage = `url(${JSON.stringify(first.poster)})`;
      const wrapper = this.host.querySelector('.trailer-videos');
      this.videos = this.story.scenes.map(scene => {
        const video = document.createElement('video');
        video.muted = true;
        video.playsInline = true;
        video.preload = 'metadata';
        video.disablePictureInPicture = true;
        video.setAttribute('aria-hidden', 'true');
        video.src = scene.url;
        wrapper.append(video);
        return video;
      });
      this.caption = this.host.querySelector('.trailer-caption');
      this.title = this.host.querySelector('.trailer-poster-title');
      this.button = this.host.querySelector('.trailer-play');
      this.message = this.host.querySelector('.trailer-message');
      this.progress = this.host.querySelector('.trailer-progress');
      this.button.addEventListener('click', () => this.play());
    }

    async waitForVideo(video) {
      if (video.readyState >= 2) return;
      await new Promise((resolve, reject) => {
        const timeout = setTimeout(() => { clean(); reject(new Error(t('video_timeout'))); }, 18000);
        const ready = () => { clean(); resolve(); };
        const failure = () => { clean(); reject(new Error(t('video_unavailable'))); };
        const clean = () => {
          clearTimeout(timeout);
          video.removeEventListener('loadeddata', ready);
          video.removeEventListener('error', failure);
        };
        video.addEventListener('loadeddata', ready);
        video.addEventListener('error', failure);
        video.preload = 'auto';
        video.load();
        if (video.error) failure();
      });
    }

    schedule(callback, delay) {
      this.timers.push(setTimeout(callback, delay));
    }

    async play() {
      if (this.playing) return;
      this.stop(false);
      this.stopped = false;
      this.playing = true;
      this.message.hidden = true;
      this.button.hidden = true;
      this.title.hidden = true;
      this.progress.style.width = '0%';
      this.host.classList.add('is-playing');
      try {
        await Promise.all(this.videos.map(video => this.waitForVideo(video)));
        if (this.stopped) return;
        this.startedAt = performance.now();
        this.showScene(0);
        if (this.audio) { this.audio.currentTime = 0; this.audio.play().catch(() => {}); }
        this.frame();
      } catch (error) {
        if (!this.stopped) this.fail(error.message);
      }
    }

    showScene(index) {
      if (this.stopped) return;
      const scene = this.story.scenes[index];
      if (!scene) { this.finish(); return; }
      const video = this.videos[index];
      video.currentTime = 0;
      video.playbackRate = scene.speed;
      video.style.transform = `scale(${scene.zoom}) translateX(${scene.shift}%)`;
      video.style.filter = `brightness(.88) hue-rotate(${scene.hue}deg)`;
      video.classList.add('visible');
      this.poster.hidden = true;
      this.caption.textContent = scene.caption;
      this.caption.className = `trailer-caption enter ${scene.caption_style || 'center'}`;
      this.host.dataset.transition = scene.transition;
      video.play().catch(error => this.fail(error.message));
      if (index > 0) {
        const previous = this.videos[index - 1];
        this.schedule(() => { previous.classList.remove('visible'); previous.pause(); }, 480);
      }
      this.schedule(() => this.showScene(index + 1), scene.duration * 1000);
    }

    frame() {
      if (this.stopped) return;
      const elapsed = (performance.now() - this.startedAt) / 1000;
      this.progress.style.width = `${Math.min(100, elapsed / this.story.duration * 100)}%`;
      this.frameId = requestAnimationFrame(() => this.frame());
    }

    finish() {
      this.stop(false);
      this.progress.style.width = '100%';
      this.button.textContent = '↻';
      this.button.hidden = false;
      this.title.hidden = false;
      this.caption.textContent = '';
    }

    fail(message) {
      this.stop(false);
      this.message.textContent = message;
      this.message.hidden = false;
      this.button.textContent = '↻';
      this.button.hidden = false;
      this.title.hidden = false;
    }

    stop(removeAppearance = true) {
      this.stopped = true;
      this.playing = false;
      this.timers.forEach(clearTimeout);
      this.timers = [];
      if (this.frameId) cancelAnimationFrame(this.frameId);
      this.videos.forEach(video => { video.pause(); video.classList.remove('visible'); });
      if (this.audio) { this.audio.pause(); this.audio.currentTime = 0; }
      if (removeAppearance) this.host.classList.remove('is-playing');
    }

    destroy() {
      this.stop();
      this.videos.forEach(video => { video.removeAttribute('src'); video.load(); });
    }
  }

  window.MovieGeneratorTrailer = TrailerPlayer;
})();
