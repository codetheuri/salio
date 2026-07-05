document.addEventListener("DOMContentLoaded", function() {
    // Pagination dropdown handler
    const selects = document.querySelectorAll(".per-page-select");
    selects.forEach(select => {
        select.addEventListener("change", function() {
            window.location.href = "?page=1&limit=" + this.value;
        });
    });
});
