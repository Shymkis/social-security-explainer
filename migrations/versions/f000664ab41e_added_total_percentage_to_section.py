"""added total percentage to section

Revision ID: f000664ab41e
Revises: b6b2dfe3a998
Create Date: 2024-02-26 00:31:06.288423

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = 'f000664ab41e'
down_revision = 'b6b2dfe3a998'
branch_labels = None
depends_on = None


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('section', schema=None) as batch_op:
        batch_op.add_column(sa.Column('total_percentage', sa.Float(), nullable=True))

    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('section', schema=None) as batch_op:
        batch_op.drop_column('total_percentage')

    # ### end Alembic commands ###