from .config import config
from .factory import StorageFactory
from .client import get_supabase_client
from .supabase import SupabaseStorage
from .r2 import R2Storage


# Register providers
StorageFactory.register(
    "supabase",
    SupabaseStorage,
)
StorageFactory.register(
    "r2",
    R2Storage,
)


def _create_provider():
    provider = config.provider

    if provider == "supabase":
        return StorageFactory.create(
            "supabase",
            get_supabase_client(),
        )

    elif provider == "r2":
        return StorageFactory.create(
            "r2",
        )

    elif provider == "both":
        raise NotImplementedError(
            "'both' mode will be implemented after validating R2."
        )

    raise ValueError(
        f"Unknown storage provider: {provider}"
    )


storage = _create_provider()