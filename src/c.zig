pub const c = @cImport({
    @cInclude("tr.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("time.h");
    @cInclude("sys/stat.h");
});
