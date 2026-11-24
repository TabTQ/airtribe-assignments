import json
import os
from django.conf import settings
from rest_framework.decorators import api_view
from django.http import JsonResponse
from issues.models import Reporter, Issue, CriticalIssue, LowPriorityIssue

ISSUES_FILE = os.path.join(settings.BASE_DIR, 'issues.json')
REPORTERS_FILE = os.path.join(settings.BASE_DIR, 'reporters.json')

def load_data(path):
    if not os.path.exists(path):
        return []
    try:
        with open(path, 'r') as f:
            return json.load(f)
    except Exception as e:
        print(f"Error loading data from {path}: {e}")
    return []

def save_data(path, records):
    try:
        with open(path, 'w') as f:
            json.dump(records, f, indent=2)
    except Exception as e:
        print(f"Error saving data to {path}: {e}")

@api_view(['GET', 'POST'])
def reporters(request):

    reporter_list = load_data(REPORTERS_FILE)

    if request.method == 'POST':
        data = request.data

        missing = [
            k for k in ('id', 'name', 'email', 'team') 
            if k not in data
        ]
        if missing:
            return JsonResponse({'error': f"Missing fields: {', '.join(missing)}"}, status=400)

        reporter = Reporter(data['id'], data['name'], data['email'], data['team'])

        try:
            reporter.validate()
        except ValueError as e:
            return JsonResponse({'error': str(e)}, status=400)

        if get_reporter_by_id(reporter_list, data['id']) is not None:
            return JsonResponse({'error': 'Reporter with this ID already exists'}, status=400)
        
        reporter_list.append(reporter.to_dict())
        save_data(REPORTERS_FILE, reporter_list)

        return JsonResponse(reporter.to_dict(), status=201)
    
    reporter_id = request.GET.get('id')
    if reporter_id is None:
        return JsonResponse(reporter_list, status=200, safe=False)

    try:
        reporter_id = int(reporter_id)
    except (ValueError, TypeError):
        return JsonResponse({'error': 'Invalid reporter ID'}, status=400)

    reporter = get_reporter_by_id(reporter_list, reporter_id)
    if reporter is None:
        return JsonResponse({'error': 'Reporter not found'}, status=404)

    return JsonResponse(reporter, status=200) 

def get_reporter_by_id(reporter_list, reporter_id):
    for r in reporter_list:
        if int(reporter_id) == r['id']:
            return r
    return None

@api_view(['GET', 'POST'])
def issues(request):
    
    reporter_list = load_data(REPORTERS_FILE)

    issue_list = load_data(ISSUES_FILE)

    if request.method == 'POST':
        data = request.data

        missing = [
            k for k in ('id', 'title', 'description', 'status', 'priority', 'reporter_id') 
            if k not in data
        ]
        if missing:
            return JsonResponse({'error': f"Missing fields: {', '.join(missing)}"}, status=400)

        if data['priority'] == 'critical':
            issue = CriticalIssue(data['id'], data['title'], data['description'],
                                  data['status'], data['priority'], data['reporter_id'])
        elif data['priority'] == 'low':
            issue = LowPriorityIssue(data['id'], data['title'], data['description'],
                                     data['status'], data['priority'], data['reporter_id'])
        else:
            issue = Issue(data['id'], data['title'], data['description'],
                          data['status'], data['priority'], data['reporter_id'])

        try:
            issue.validate()
        except ValueError as e:
            return JsonResponse({'error': str(e)}, status=400)

        if get_issue_by_id(issue_list, data['id']) is not None:
            return JsonResponse({'error': 'Issue with this ID already exists'}, status=400)

        if get_reporter_by_id(reporter_list, data['reporter_id']) is None:
            return JsonResponse({'error': 'Reporter not found'}, status=404)

        issue_list.append(issue.to_dict())
        save_data(ISSUES_FILE, issue_list)

        response_data = issue.to_dict()
        response_data['message'] = issue.describe()
        return JsonResponse(response_data, status=201)

    issue_id = request.GET.get('id')
    status = request.GET.get('status')

    if issue_id is not None:
        try:
            issue_id = int(issue_id)
        except (ValueError, TypeError):
            return JsonResponse({'error': 'Invalid issue ID'}, status=400)
        issue = get_issue_by_id(issue_list, issue_id)
        if issue is None:
            return JsonResponse({'error': 'Issue not found'}, status=404)
        return JsonResponse(issue, status=200)
        
    elif status is not None:
        issues_list = get_issues_by_status(issue_list, status)
        if not issues_list:
            return JsonResponse({'Error': 'No issues found with the specified status'}, status=404)
        return JsonResponse(issues_list, status=200, safe=False)
    
    return JsonResponse(issue_list, status=200, safe=False)

def get_issue_by_id(issue_list, issue_id):
    for i in issue_list:
        if int(issue_id) == i['id']:
            return i
    return None

def get_issues_by_status(issue_list, status):
    return [i for i in issue_list if i['status'] == status]
