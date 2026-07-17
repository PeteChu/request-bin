const CopyOnFocus = {
  mounted() {
    this.handleFocus = () => {
      try {
        this.el.select();
        this.el.setSelectionRange(0, 99999);
        navigator.clipboard.writeText(this.el.value);
        this.pushEvent("copied_url", {});
      } catch (error) {
        console.error("Failed to copy text:", error);
      }
    };

    this.el.addEventListener("focus", this.handleFocus);
  },
  destroyed() {
    this.el.removeEventListener("focus", this.handleFocus);
  },
};

export default CopyOnFocus;
