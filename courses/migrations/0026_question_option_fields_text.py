# Convert option/answer columns to TEXT on databases that already applied
# the old VARCHAR(5000) version of 0016 (local SQLite).

from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0025_exam_allow_calculator"),
    ]

    operations = [
        migrations.AlterField(
            model_name="question",
            name="option_a",
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name="question",
            name="option_b",
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name="question",
            name="option_c",
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name="question",
            name="option_d",
            field=models.TextField(blank=True),
        ),
        migrations.AlterField(
            model_name="question",
            name="correct_answer",
            field=models.TextField(
                blank=True,
                help_text="For choice: A/B/C/D or A,B for multiple",
            ),
        ),
    ]
