const CopyOnClick = {
  mounted() {
    this.handleClick = () => {
      const text = this.el.dataset.copyText || "";
      navigator.clipboard.writeText(text).then(
        () => this.pushEvent("copied", {}),
        () => this.pushEvent("copied", {})
      );
    };

    this.el.addEventListener("click", this.handleClick);
  },
  destroyed() {
    this.el.removeEventListener("click", this.handleClick);
  },
};

export default CopyOnClick;
