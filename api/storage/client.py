from functools import lru_cache

from supabase import Client, create_client

from .config import config


@lru_cache(maxsize=1)
def get_supabase_client() -> Client:
    """
    Returns a singleton-like cached Supabase client.
    The client is created only once per process.
    """

    return create_client(
        config.supabase_url,
        config.supabase_key,
    )