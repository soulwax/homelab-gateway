// Animated particle background
const canvas = document.getElementById('bg');
const ctx = canvas.getContext('2d');

let W, H, particles;

function resize() {
  W = canvas.width  = window.innerWidth;
  H = canvas.height = window.innerHeight;
}

function initParticles() {
  particles = Array.from({ length: 60 }, () => ({
    x: Math.random() * W,
    y: Math.random() * H,
    r: Math.random() * 1.5 + 0.3,
    dx: (Math.random() - 0.5) * 0.4,
    dy: (Math.random() - 0.5) * 0.4,
    alpha: Math.random() * 0.5 + 0.1,
  }));
}

function draw() {
  ctx.clearRect(0, 0, W, H);
  for (const p of particles) {
    p.x += p.dx;
    p.y += p.dy;
    if (p.x < 0) p.x = W;
    if (p.x > W) p.x = 0;
    if (p.y < 0) p.y = H;
    if (p.y > H) p.y = 0;

    ctx.beginPath();
    ctx.arc(p.x, p.y, p.r, 0, Math.PI * 2);
    ctx.fillStyle = `rgba(124,58,237,${p.alpha})`;
    ctx.fill();
  }

  // draw faint connection lines
  for (let i = 0; i < particles.length; i++) {
    for (let j = i + 1; j < particles.length; j++) {
      const dx = particles[i].x - particles[j].x;
      const dy = particles[i].y - particles[j].y;
      const dist = Math.sqrt(dx * dx + dy * dy);
      if (dist < 120) {
        ctx.beginPath();
        ctx.moveTo(particles[i].x, particles[i].y);
        ctx.lineTo(particles[j].x, particles[j].y);
        ctx.strokeStyle = `rgba(124,58,237,${0.12 * (1 - dist / 120)})`;
        ctx.lineWidth = 0.5;
        ctx.stroke();
      }
    }
  }

  requestAnimationFrame(draw);
}

window.addEventListener('resize', () => { resize(); initParticles(); });
resize();
initParticles();
draw();

// Clock
function updateClock() {
  document.getElementById('clock').textContent =
    new Date().toLocaleTimeString('en-GB');
}
setInterval(updateClock, 1000);
updateClock();

// Uptime
const start = Date.now();
function updateUptime() {
  const s = Math.floor((Date.now() - start) / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  document.getElementById('uptime').textContent =
    h > 0 ? `${h}h ${m}m ${sec}s` : m > 0 ? `${m}m ${sec}s` : `${sec}s`;
}
setInterval(updateUptime, 1000);

// Visitor IP via public API
fetch('https://api.ipify.org?format=json')
  .then(r => r.json())
  .then(d => { document.getElementById('visitor-ip').textContent = d.ip; })
  .catch(() => { document.getElementById('visitor-ip').textContent = 'unknown'; });
