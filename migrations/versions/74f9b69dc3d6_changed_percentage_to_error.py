"""changed percentage to error

Revision ID: 74f9b69dc3d6
Revises: f000664ab41e
Create Date: 2024-02-26 21:00:32.242227

"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '74f9b69dc3d6'
down_revision = 'f000664ab41e'
branch_labels = None
depends_on = None


def upgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('section', schema=None) as batch_op:
        batch_op.add_column(sa.Column('total_error', sa.Float(), nullable=True))
        batch_op.drop_column('total_percentage')

    with op.batch_alter_table('selection', schema=None) as batch_op:
        batch_op.add_column(sa.Column('error', sa.Float(), nullable=True))
        batch_op.drop_column('percentage')

    # ### end Alembic commands ###


def downgrade():
    # ### commands auto generated by Alembic - please adjust! ###
    with op.batch_alter_table('selection', schema=None) as batch_op:
        batch_op.add_column(sa.Column('percentage', sa.FLOAT(), nullable=True))
        batch_op.drop_column('error')

    with op.batch_alter_table('section', schema=None) as batch_op:
        batch_op.add_column(sa.Column('total_percentage', sa.FLOAT(), nullable=True))
        batch_op.drop_column('total_error')

    # ### end Alembic commands ###
