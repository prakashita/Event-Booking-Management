"""
Lightweight migration runner for MongoDB.
Runs numbered scripts in migrations/ once, tracked in the 'migrations' collection.
Usage: python -m migrations.run
"""
import asyncio
import os
import sys

# Add parent directory so imports work
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from motor.motor_asyncio import AsyncIOMotorClient


MIGRATIONS_COLLECTION = "migrations"
MIGRATIONS_DIR = os.path.join(os.path.dirname(__file__))


def get_migration_files():
    """Return sorted list of (name, path) for *.py files, excluding __init__ and run."""
    files = []
    for f in os.listdir(MIGRATIONS_DIR):
        if f.endswith(".py") and f not in ("__init__.py", "run.py") and f[0].isdigit():
            path = os.path.join(MIGRATIONS_DIR, f)
            if os.path.isfile(path):
                name = f.replace(".py", "")
                files.append((name, path))
    return sorted(files, key=lambda x: x[0])


async def run_migrations():
    import database
    await database.init_db()
    db = database.client[database.DB_NAME]
    coll = db[MIGRATIONS_COLLECTION]

    run = await coll.find_one({"_id": "run"})
    applied = set(run["applied"]) if run else set()

    for name, path in get_migration_files():
        if name in applied:
            print(f"Skip (already applied): {name}")
            continue
        print(f"Running: {name}")
        try:
            # Load and run migration's upgrade()
            import importlib.util
            spec = importlib.util.spec_from_file_location(name, path)
            mod = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(mod)
            if hasattr(mod, "upgrade"):
                await mod.upgrade(db)
            await coll.update_one(
                {"_id": "run"},
                {"$addToSet": {"applied": name}},
                upsert=True,
            )
            print(f"  OK: {name}")
        except Exception as e:
            print(f"  FAIL: {name} - {e}")
            raise

    await database.close_db()
    print("Migrations complete.")


if __name__ == "__main__":
    asyncio.run(run_migrations())
