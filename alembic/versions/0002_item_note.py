"""Add a note to items

Revision ID: 0002_item_note
Revises: 0001_items
"""

import sqlalchemy as sa
from alembic import op

revision = "0002_item_note"
down_revision = "0001_items"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("items", sa.Column("note", sa.String(200), nullable=True))


def downgrade() -> None:
    op.drop_column("items", "note")
