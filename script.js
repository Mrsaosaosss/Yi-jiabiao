// ===== 导航栏滚动效果 =====
const navbar = document.querySelector('.navbar');
const navLinks = document.querySelectorAll('.nav-menu a');
const sections = document.querySelectorAll('section[id]');

function updateActiveNav() {
    const scrollY = window.scrollY;

    sections.forEach((section) => {
        const top = section.offsetTop - 100;
        const bottom = top + section.offsetHeight;
        const id = section.getAttribute('id');

        if (scrollY >= top && scrollY < bottom) {
            navLinks.forEach((link) => {
                link.classList.remove('active');
                if (link.getAttribute('href') === `#${id}`) {
                    link.classList.add('active');
                }
            });
        }
    });
}

window.addEventListener('scroll', updateActiveNav);

// ===== 移动端菜单切换 =====
const navToggle = document.querySelector('.nav-toggle');
const navMenu = document.querySelector('.nav-menu');

navToggle.addEventListener('click', () => {
    navMenu.classList.toggle('open');
});

// 点击菜单项后关闭菜单
navLinks.forEach((link) => {
    link.addEventListener('click', () => {
        navMenu.classList.remove('open');
    });
});

// ===== 滚动渐入动画 =====
const fadeEls = document.querySelectorAll(
    '.skill-card, .timeline-item, .about-text, .about-info'
);
fadeEls.forEach((el) => el.classList.add('fade-in'));

const observer = new IntersectionObserver(
    (entries) => {
        entries.forEach((entry) => {
            if (entry.isIntersecting) {
                entry.target.classList.add('visible');
                observer.unobserve(entry.target);
            }
        });
    },
    { threshold: 0.15 }
);

fadeEls.forEach((el) => observer.observe(el));

// ===== 联系表单提交 =====
const contactForm = document.getElementById('contactForm');

contactForm.addEventListener('submit', function (e) {
    e.preventDefault();

    const btn = contactForm.querySelector('button');
    const originalText = btn.textContent;
    btn.textContent = '发送中...';
    btn.disabled = true;

    // 模拟发送
    setTimeout(() => {
        showToast('消息已发送！感谢您的联系。');
        contactForm.reset();
        btn.textContent = originalText;
        btn.disabled = false;
    }, 800);
});

function showToast(message) {
    let toast = document.querySelector('.toast');
    if (!toast) {
        toast = document.createElement('div');
        toast.className = 'toast';
        document.body.appendChild(toast);
    }

    toast.textContent = message;
    toast.classList.add('show');

    clearTimeout(toast._timeout);
    toast._timeout = setTimeout(() => {
        toast.classList.remove('show');
    }, 2500);
}
