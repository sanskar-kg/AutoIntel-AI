document.querySelectorAll('[data-year]').forEach((el) => {
  el.textContent = new Date().getFullYear();
});

document.querySelectorAll('[data-menu]').forEach((button) => {
  button.addEventListener('click', () => {
    const links = document.querySelector('[data-nav-links]');
    links?.classList.toggle('is-open');
  });
});
