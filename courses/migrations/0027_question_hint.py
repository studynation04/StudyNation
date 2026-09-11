from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("courses", "0026_question_option_fields_text"),
    ]

    operations = [
        migrations.AddField(
            model_name="question",
            name="hint",
            field=models.TextField(
                blank=True,
                default="",
                help_text="Optional clue shown when a student taps Hint during practice.",
            ),
        ),
    ]
