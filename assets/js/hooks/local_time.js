const LocalTime = {
  mounted() {
    this.convertToLocalTime();
  },
  updated() {
    this.convertToLocalTime();
  },
  convertToLocalTime() {
    const expiresAtElement = this.el.querySelector("[data-expires-at]");
    if (expiresAtElement) {
      const isoDate = expiresAtElement.getAttribute("data-expires-at");
      const localDate = new Date(isoDate).toLocaleString();
      expiresAtElement.textContent = localDate;
    }
  },
};

export default LocalTime;
