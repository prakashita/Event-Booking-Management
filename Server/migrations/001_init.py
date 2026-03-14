"""
Initial migration placeholder.
Run explicitly to ensure migration tracking is set up.
Indexes are defined in Beanie model Settings and created on app init.
"""


async def upgrade(db):
    """No-op; indexes come from Beanie init_beanie."""
    pass
