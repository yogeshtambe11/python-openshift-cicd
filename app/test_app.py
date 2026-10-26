import unittest
from app import app

class BasicTests(unittest.TestCase):
    def setUp(self):
        self.client = app.test_client()

    def test_health(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)

if __name__ == "__main__":
    unittest.main()
