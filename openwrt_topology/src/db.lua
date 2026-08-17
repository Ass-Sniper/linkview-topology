local sqlite3 = require("lsqlite3")

local M = {}

function M.open(path)
    local db = assert(sqlite3.open(path))
    db:busy_timeout(5000)
    assert(db:exec("PRAGMA foreign_keys=ON; PRAGMA journal_mode=WAL; PRAGMA synchronous=NORMAL;") == sqlite3.OK)
    return db
end

function M.exec_file(db, path)
    local file = assert(io.open(path, "rb"))
    local sql = file:read("*a")
    file:close()
    local rc = db:exec(sql)
    assert(rc == sqlite3.OK, db:errmsg())
end

function M.transaction(db, fn)
    assert(db:exec("BEGIN IMMEDIATE") == sqlite3.OK, db:errmsg())
    local ok, result = xpcall(fn, debug.traceback)
    if ok then
        assert(db:exec("COMMIT") == sqlite3.OK, db:errmsg())
        return result
    end
    db:exec("ROLLBACK")
    error(result)
end

function M.one(db, sql, ...)
    local stmt = assert(db:prepare(sql))
    assert(stmt:bind_values(...) == sqlite3.OK)
    local row
    if stmt:step() == sqlite3.ROW then row = stmt:get_named_values() end
    stmt:finalize()
    return row
end

return M
