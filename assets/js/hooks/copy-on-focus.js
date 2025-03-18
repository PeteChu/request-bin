const CopyOnFocus = {
  mounted() {
    this.el.addEventListener("focus", () => {
      try {
        this.el.select();
        this.el.setSelectionRange(0, 99999);
        navigator.clipboard.writeText(this.el.value);

        console.log(this.pushEvent("copied_url", {}));
      } catch (error) {
        console.error("Failed to copy text:", err);
      }
    });
  },
  destroyed() {
    // Clean up the event listener when the hook is destroyed
    this.el.removeEventListener("focus", () => {});
  },
};

export default CopyOnFocus;
