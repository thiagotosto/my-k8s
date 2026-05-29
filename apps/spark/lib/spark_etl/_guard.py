import functools
from pydantic import BaseModel


def _type_guard(fn):
    @functools.wraps(fn)
    def wrapper(self, *args, **kwargs):
        options = args[1] if len(args) > 1 else kwargs.get("options")
        if not isinstance(options, BaseModel):
            raise TypeError(
                f"{type(self).__name__}.{fn.__name__} expects a pydantic BaseModel "
                f"for options, got {type(options).__name__}"
            )
        return fn(self, *args, **kwargs)
    return wrapper
