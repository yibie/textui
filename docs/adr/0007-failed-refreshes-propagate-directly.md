# Failed refreshes propagate directly

TextUI does not retain a last-good frame or implement presentation rollback.
Frame production, expansion, validation, and measurement occur before the real
buffer is changed, so an error there naturally leaves its old contents alone.
Once real presentation begins, any error is re-signaled immediately and may
leave partial output; the caller fixes the cause and invokes `textui-refresh` to
rebuild the whole buffer. TextUI does not replace failures with an error page.
