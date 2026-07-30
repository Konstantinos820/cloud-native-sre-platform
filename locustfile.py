import random
import uuid

from locust import HttpUser, task, between


class FastAPIUser(HttpUser):
    """
    Load profile for the sre-platform-app FastAPI service.

    Mix is weighted towards reads (list/get users), with a meaningful share
    of writes (user registration, which exercises the DB commit path) and a
    light background of health checks -- closer to a real traffic mix than
    hammering a single endpoint.
    """

    wait_time = between(0.1, 0.5)

    def on_start(self):
        # Seed one user immediately so GET /users/{id} has something to
        # fetch even in the first few seconds of the run.
        self.last_user_id = None
        self.create_user()

    def create_user(self):
        email = f"loadtest-{uuid.uuid4().hex[:12]}@example.com"
        with self.client.post(
            "/users",
            json={"email": email, "full_name": "Load Test User"},
            catch_response=True,
        ) as response:
            if response.status_code == 201:
                self.last_user_id = response.json().get("id")
            elif response.status_code == 409:
                # Duplicate email under high concurrency is expected, not a failure.
                response.success()

    @task(5)
    def list_users(self):
        self.client.get("/users", name="/users [list]")

    @task(3)
    def get_user(self):
        user_id = self.last_user_id or random.randint(1, 50)
        self.client.get(f"/users/{user_id}", name="/users/[id]")

    @task(2)
    def register_user(self):
        self.create_user()

    @task(1)
    def health_check(self):
        self.client.get("/health/ready")