from flask import Flask, flash, g, render_template, request, session, jsonify, url_for, redirect, current_app
from flask_login import login_user, logout_user, current_user, login_required, LoginManager
from flask_sqlalchemy import SQLAlchemy
from flask_migrate import Migrate
from flask_wtf import FlaskForm
from wtforms  import StringField, PasswordField, SubmitField
from wtforms.validators import DataRequired
from sqlalchemy import JSON
from random import choice, randint
from datetime import datetime, timedelta

PROTOCOLS = ["none", "placebic", "actionable"]

# forms.py
class LoginForm(FlaskForm):
	mturk_id = StringField("MTurk ID", validators = [DataRequired()])
	submit = SubmitField("Begin Experiment")

# configuration.py
class Config(object):
	"""
	Configuration base, for all environments.
	"""
	DEBUG = False
	TESTING = False
	SQLALCHEMY_DATABASE_URI = "sqlite:///application.db"
	BOOTSTRAP_FONTAWESOME = True
	SECRET_KEY = "MINHACHAVESECRETA"
	CSRF_ENABLED = True
	SQLALCHEMY_TRACK_MODIFICATIONS = True

	#Get your reCaptche key on: https://www.google.com/recaptcha/admin/create
	#RECAPTCHA_PUBLIC_KEY = "6LffFNwSAAAAAFcWVy__EnOCsNZcG2fVHFjTBvRP"
	#RECAPTCHA_PRIVATE_KEY = "6LffFNwSAAAAAO7UURCGI7qQ811SOSZlgU69rvv7"

class ProductionConfig(Config):
	SQLALCHEMY_DATABASE_URI = "mysql://user@localhost/foo"
	SQLALCHEMY_TRACK_MODIFICATIONS = False

class DevelopmentConfig(Config):
	DEBUG = True

class TestingConfig(Config):
	TESTING = True

app = Flask(__name__)
#Configuration of application, see configuration.py, choose one and uncomment.
#app.config.from_object("configuration.ProductionConfig")
app.config.from_object(DevelopmentConfig)
#app.config.from_object("configuration.TestingConfig")

db = SQLAlchemy(app)
migrate = Migrate(app, db)

lm = LoginManager()
lm.setup_app(app)
lm.login_view = "login"

# util_views.py
class User(db.Model):
    mturk_id = db.Column(db.String(20), primary_key=True, unique=True)
    experiment_completed = db.Column(db.Boolean, default=False)
    failed_attention_checks = db.Column(db.Boolean, default=False)
    start_time = db.Column(db.DateTime)
    end_time = db.Column(db.DateTime)
    consent = db.Column(db.Boolean, default=False)
    completion_code = db.Column(db.Integer, default=-1)
    protocol = db.Column(db.String(20))
    compensation = db.Column(db.Float, default=0.00)

    def is_authenticated(self):
        return True

    def is_active(self):
        return True

    def is_anonymous(self):
        return False

    def get_id(self):
        return str(self.mturk_id)

    def __repr__(self):
        return "<User MTURK ID: %r>" % (self.mturk_id)
    
class Survey(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    mturk_id = db.Column(db.String(20), db.ForeignKey("user.mturk_id"))
    type = db.Column(db.String(20))
    data = db.Column(JSON)
    timestamp = db.Column(db.DateTime)

class Puzzle(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    fen = db.Column(db.String(100))
    order = db.Column(db.Integer)
    moves = db.Column(db.String(20))
    theme = db.Column(db.String(20))
    section = db.Column(db.String(20))

class Explanation(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    puzzle_id = db.Column(db.Integer, db.ForeignKey("puzzle.id"))
    move_num = db.Column(db.Integer)
    protocol = db.Column(db.String(20))
    mistake = db.Column(db.Boolean)
    reason = db.Column(db.String(200))

class Section(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    mturk_id = db.Column(db.String(20), db.ForeignKey("user.mturk_id"))
    section = db.Column(db.String(20))
    protocol = db.Column(db.String(20))
    start_time = db.Column(db.DateTime)
    end_time = db.Column(db.DateTime)
    duration = db.Column(db.Integer)
    successes = db.Column(db.Integer)
    num_puzzles = db.Column(db.Integer)

class Move(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    mturk_id = db.Column(db.String(20), db.ForeignKey("user.mturk_id"))
    section_id = db.Column(db.Integer, db.ForeignKey("section.id"))
    puzzle_id = db.Column(db.Integer, db.ForeignKey("puzzle.id"))
    move_num = db.Column(db.Integer)
    move = db.Column(db.String(5))
    start_time = db.Column(db.DateTime)
    end_time = db.Column(db.DateTime)
    duration = db.Column(db.Integer)
    mistake = db.Column(db.Boolean)

@lm.user_loader
def load_user(user_id):
    return User.query.get(user_id)

def row2dict(r):
    return {c.name: str(getattr(r, c.name)) for c in r.__table__.columns}

# vvv   APP ROUTES   vvv

# Utility function to clear session data and logout
@app.route("/clear_session_and_logout/")
def clear_session_and_logout():
    logout_user()
    session.clear()
    flash("You have either run out of time or have violated the terms of the experiment.")
    return redirect(url_for("login"))

def is_session_expired():
    expiry_time = session.get("expiry_time")
    if expiry_time:
        expiry_time = datetime.strptime(expiry_time, "%Y-%m-%d %H:%M:%S")
        if datetime.now() > expiry_time:
            return True
    return False

@app.before_request
def check_session_expiry():
    if current_user.is_authenticated and is_session_expired():
        clear_session_and_logout()
    if session.get("failed_attention_checks") is not None and session.get("failed_attention_checks") >= 2:
        # Add to user model
        user = User.query.filter_by(mturk_id=session["mturk_id"]).first()
        user.failed_attention_checks = True
        db.session.commit()
        clear_session_and_logout()

# Index page
@app.route("/")
def index():
    if not current_user.is_authenticated or not session.get("login_completed"):
        return redirect(url_for("login"))
    else:
        return redirect(url_for("consent"))

#Login page
@app.route("/login/", methods=["GET", "POST"])
def login():
    if current_user.is_authenticated:
        return redirect(url_for("consent"))

    form = LoginForm()
    if form.validate_on_submit():
        mturk_id = form.mturk_id.data
        user = User.query.filter_by(mturk_id=mturk_id).first()

        if not user:
            new_user = User(mturk_id=mturk_id, start_time = datetime.now())
            db.session.add(new_user)
            db.session.commit()

            login_user(new_user)
            flash("Login successful! You are now registered in the system.")

            session["mturk_id"] = mturk_id
            session["login_completed"] = True
            session["login_time"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            session["expiry_time"] = (datetime.now() + timedelta(minutes=45)).strftime("%Y-%m-%d %H:%M:%S")
            session["experiment_completed"] = False

            return redirect(url_for("consent"))
        else:
            if user.experiment_completed:
                flash("Error! You have already completed the experiment.")
            else:
                flash("Error! MTurk ID already used. Contact the researchers if you believe this to be in error.")
            return redirect(url_for("login"))

    return render_template("login.html", title="Sign In", form=form)

@app.route("/consent/", methods=["GET", "POST"])
def consent():
    if not current_user.is_authenticated or session.get("consent") == True:
        clear_session_and_logout()

    return render_template("consent.html")

@app.route("/consent/submit/", methods=["POST"])
def consent_submit():
    if not current_user.is_authenticated or session.get("consent") == True:
        print("Not authenticated or consent already given")
        return redirect(url_for("login"))

    if request.method == "POST":
        if request.form.get("consent") == "True":
            current_user.consent = True
            session["consent"] = True
            db.session.commit()
            
            # Assign a random intervention condition
            session["protocol"] = choice(PROTOCOLS)
            # Add to user model
            user = User.query.filter_by(mturk_id=session["mturk_id"]).first()
            user.protocol = session["protocol"]
            db.session.commit()
            
            print("Protocol: " + str(session["protocol"]))

            return redirect(url_for("demographics_survey"))
        else:
            print("Consent not given")
            return clear_session_and_logout()

@app.route("/demographics_survey/", methods=["GET", "POST"])
def demographics_survey():
    if not current_user.is_authenticated or not session.get("consent"):
        return redirect(url_for("clear_session_and_logout"))
    elif Survey.query.filter_by(mturk_id=session["mturk_id"], type="demographics").first():
        return redirect(url_for("clear_session_and_logout"))
    else:
        session["demo_survey_loaded"] = True
        return render_template("demographics_survey.html")

@app.route("/demographics_survey/submit/", methods=["POST"])
def demographics_survey_submit():
    if not current_user.is_authenticated or not session.get("consent"):
        return redirect(url_for("clear_session_and_logout"))
    
    # Check if the form was already submitted
    if Survey.query.filter_by(mturk_id=session["mturk_id"], type="demographics").first():
        return redirect(url_for("clear_session_and_logout"))
    
    if request.method == "POST":
        
        # Get data from the form as a dictionary
        demographics = {}
        demographics["age"] = request.form.get("q1")
        demographics["gender"] = request.form.get("q2")
        demographics["ethnicity"] = request.form.get("q3")
        demographics["education"] = request.form.get("q4")
        demographics["attention-check"] = request.form.get("q5")
        demographics["chess-skill"] = request.form.get("q6")
        
        failed_attention_checks = 0
        if demographics["attention-check"] != "4":
            failed_attention_checks += 1
        session["failed_attention_checks"] = failed_attention_checks
        print("Failed attention checks: " + str(failed_attention_checks))
        
        # Save survey to database
        survey = Survey(
            mturk_id = session["mturk_id"],
            type = "demographics",
            data = demographics,
            timestamp = datetime.now()
        )
        db.session.add(survey)
        db.session.commit()
        
        return redirect(url_for("key_info"))

@app.route("/key_info/")
@login_required
def key_info():
    if not current_user.is_authenticated or not session.get("consent") == True:
        print("User not authenticated or consented.")
        return redirect(url_for("login"))

    return render_template("key_info.html")

@app.route("/practice/")
@login_required
def practice():
    if not current_user.is_authenticated or not session.get("consent") == True:
        print("User not authenticated or consented.")
        return redirect(url_for("login"))

    if session.get("practice_page_loaded"):
        print("User is reloading practice page.")
        return redirect(url_for("clear_session_and_logout"))

    session["practice_page_loaded"] = True

    session["section"] = "practice"
    return render_template("chess.html", section=session["section"], protocol=session["protocol"])

@app.route("/testing/")
@login_required
def testing():
    if not current_user.is_authenticated or not session.get("consent") == True:
        print("User not authenticated or consented.")
        return redirect(url_for("login"))

    if session.get("testing_page_loaded"):
        print("User is reloading testing page.")
        return redirect(url_for("clear_session_and_logout"))

    session["testing_page_loaded"] = True

    session["section"] = "testing"
    session["protocol"] = "none"
    return render_template("chess.html", section=session["section"], protocol=session["protocol"])

@app.route("/get_puzzles/", methods=["POST"])
def get_puzzles():
    # Create section for the user
    sect = Section(
        mturk_id = session["mturk_id"],
        section = session["section"],
        protocol = session["protocol"],
        start_time = datetime.now(),
        successes = 0,
        num_puzzles = 0
    )
    db.session.add(sect)
    db.session.commit()
    session["section_id"] = sect.id

    puzzle_rows = Puzzle.query.filter_by(section=session["section"]).order_by(Puzzle.order).all()
    puzzle_dicts = [row2dict(p) for p in puzzle_rows]
    return jsonify(puzzle_dicts)

@app.route("/log_move/", methods=["POST"])
def log_move():
    data = request.get_json()
    exp_row = Explanation.query.filter_by(
        puzzle_id=data["puzzle_id"], move_num=data["move_num"],
        protocol=session["protocol"], mistake=data["mistake"]
    ).first()
    exp_dict = row2dict(exp_row) if exp_row else None

    sect = Section.query.get(session["section_id"])
    sect.successes = data["successes"]
    sect.num_puzzles = data["puzzles"]

    move = Move(
        mturk_id = session["mturk_id"],
        section_id = session["section_id"],
        puzzle_id = data["puzzle_id"],
        move_num = data["move_num"],
        move = data["move"],
        start_time = datetime.fromtimestamp(data["move_start"]/1000),
        end_time = datetime.fromtimestamp(data["move_end"]/1000),
        duration = data["move_duration"],
        mistake = data["mistake"]
    )
    db.session.add(move)
    
    db.session.commit()
    return jsonify(exp_dict)

@app.route("/log_theme_answer/", methods=["POST"])
def log_theme_answer():
    data = request.get_json()
    surveys = Survey.query.filter_by(mturk_id=session["mturk_id"], type="theme_question").all()
    for s in surveys:
        if s.data["puzzle_id"] == data["puzzle_id"]:
            s.data = data
            s.timestamp = datetime.now()
            db.session.commit()
            return "Updated successfully"
    survey = Survey(
        mturk_id = session["mturk_id"],
        type = "theme_question",
        data = data,
        timestamp = datetime.now()
    )
    db.session.add(survey)
    db.session.commit()
    return "Added successfully"

@app.route("/log_section/", methods=["POST"])
def log_section():
    data = request.get_json()
    sect = Section.query.get(session["section_id"])
    sect.end_time = datetime.fromtimestamp(data["end_time"]/1000)
    sect.duration = data["duration"]
    db.session.commit()
    if session.get("section") == "testing":
        return url_for("final_survey")
    return url_for("testing")

@app.route("/final_survey/", methods=["GET", "POST"])
def final_survey():
    if not current_user.is_authenticated or not session.get("consent"):
        return redirect(url_for("clear_session_and_logout"))
    elif Survey.query.filter_by(mturk_id=session["mturk_id"], type="final_survey").first():
        return redirect(url_for("clear_session_and_logout"))
    else:
        session["final_survey_loaded"] = True
        return render_template("final_survey.html", protocol=User.query.filter_by(mturk_id=session["mturk_id"]).first().protocol)

@app.route("/final_survey/submit/", methods=["POST"])
def final_survey_submit():
    if not current_user.is_authenticated or not session.get("consent"):
        return redirect(url_for("clear_session_and_logout"))
    
    # Check if the form was already submitted
    if Survey.query.filter_by(mturk_id=session["mturk_id"], type="final_survey").first():
        return redirect(url_for("clear_session_and_logout"))
    
    if request.method == "POST":
        
        # Get data from the form as a dictionary
        final_survey = {}
        final_survey["sat-outcome-1"] = request.form.get("q11")
        final_survey["sat-outcome-2"] = request.form.get("q12")
        final_survey["sat-outcome-3"] = request.form.get("q13")
        final_survey["sat-agent-1"] = request.form.get("q21")
        final_survey["sat-agent-2"] = request.form.get("q22")
        final_survey["sat-agent-3"] = request.form.get("q23")
        final_survey["exp-power-1"] = request.form.get("q31") if request.form.get("q31") else "0"
        final_survey["exp-power-2"] = request.form.get("q32") if request.form.get("q32") else "0"
        final_survey["exp-power-3"] = request.form.get("q33") if request.form.get("q33") else "0"
        final_survey["attention-check-1"] = request.form.get("q41")
        final_survey["attention-check-2"] = request.form.get("q42")
        
        if final_survey["attention-check-1"] != "7":
            session["failed_attention_checks"] += 1
        if final_survey["attention-check-2"] not in ["1", "2", "3"]:
            session["failed_attention_checks"] += 1
        print("Failed attention checks: " + str(session["failed_attention_checks"]))
        
        # Save survey to database
        survey = Survey(
            mturk_id = session["mturk_id"],
            type = "final_survey",
            data = final_survey,
            timestamp = datetime.now()
        )
        db.session.add(survey)
        db.session.commit()

        session["experiment_completed"] = True
        
        return redirect(url_for("post_survey"))

def calculate_bonus_comp(mturker):
    test_section = Section.query.filter_by(mturk_id=mturker, section="testing").first()
    if test_section:
        user_moves = Move.query.filter_by(section_id=test_section.id).all()
        if user_moves:
            correct_moves = {}
            bonuses = {}
            for move in user_moves:
                if move.puzzle_id not in correct_moves.keys():
                    correct_moves[move.puzzle_id] = 0
                if move.puzzle_id not in bonuses.keys():
                    bonuses[move.puzzle_id] = .2
                correct_moves[move.puzzle_id] += not move.mistake
                bonuses[move.puzzle_id] = max(bonuses[move.puzzle_id] - move.mistake*.04, 0)
            for k in correct_moves:
                if correct_moves[k] < 2:
                    bonuses[k] = 0.0
            return sum(bonuses.values())
    return 0.0

@app.route("/post_survey/", methods=["GET", "POST"])
def post_survey():
    if not current_user.is_authenticated or not session.get("consent") or not session.get("experiment_completed"):
        return redirect(url_for("clear_session_and_logout"))
    else:
        session["post_survey_loaded"] = True

        user = User.query.filter_by(mturk_id=session["mturk_id"]).first()
        if not user.experiment_completed:
            base_comp = 2.5
            session["base_comp"] = base_comp
            bonus_comp = calculate_bonus_comp(session["mturk_id"])
            session["bonus_comp"] = bonus_comp
            compensation = base_comp + bonus_comp
            session["compensation"] = compensation
            completion_code = randint(1000000000, 9999999999)
            session["completion_code"] = completion_code

            user.experiment_completed = True
            user.end_time = datetime.now()
            user.compensation = compensation
            user.completion_code = completion_code
            db.session.commit()

        return render_template("post_survey.html", completion_code=session["completion_code"], base_comp=session["base_comp"], bonus_comp=session["bonus_comp"])

@app.route("/post_survey/submit/", methods=["POST"])
def post_survey_submit():
    if not current_user.is_authenticated or not session.get("consent"):
        return redirect(url_for("clear_session_and_logout"))
    
    # Check if the form was already submitted
    if Survey.query.filter_by(mturk_id=session["mturk_id"], type="feedback").first():
        return redirect(url_for("clear_session_and_logout"))
    
    if request.method == "POST":
        feedback = request.form.get("feedback")
        survey = Survey(
            mturk_id = session["mturk_id"],
            type = "feedback",
            data = feedback,
            timestamp = datetime.now()
        )
        db.session.add(survey)
        db.session.commit()

        return redirect(url_for("thanks"))

@app.route("/thanks/")
def thanks():
    if not current_user.is_authenticated or not session.get("consent") or not session.get("experiment_completed"):
        return redirect(url_for("clear_session_and_logout"))
    return render_template("thanks.html", completion_code=session["completion_code"], base_comp=session["base_comp"], bonus_comp=session["bonus_comp"])

if __name__ == "__main__":
    app.run(debug=True)
