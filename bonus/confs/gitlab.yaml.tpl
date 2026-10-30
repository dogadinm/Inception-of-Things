apiVersion: v1
kind: Service
metadata:
  name: gitlab
  namespace: gitlab
spec:
  selector:
    app.kubernetes.io/name: gitlab
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: gitlab
  namespace: gitlab
spec:
  serviceName: gitlab
  replicas: 1
  selector:
    matchLabels:
      app.kubernetes.io/name: gitlab
  template:
    metadata:
      labels:
        app.kubernetes.io/name: gitlab
    spec:
      terminationGracePeriodSeconds: 120
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
            - weight: 100
              preference:
                matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values: [k3d-CLUSTER_PLACEHOLDER-agent-0]
      containers:
        - name: gitlab
          image: GITLAB_IMAGE_PLACEHOLDER
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 80
          env:
            - name: GITLAB_ROOT_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: gitlab-credentials
                  key: root-password
            - name: GITLAB_OMNIBUS_CONFIG
              valueFrom:
                configMapKeyRef:
                  name: gitlab-config
                  key: gitlab.rb
          resources:
            requests:
              cpu: 500m
              memory: 1536Mi
            limits:
              cpu: "2"
              memory: 4Gi
          startupProbe:
            httpGet:
              path: /-/readiness
              port: http
              httpHeaders:
                - name: Host
                  value: gitlab.local
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 120
          readinessProbe:
            httpGet:
              path: /-/readiness
              port: http
              httpHeaders:
                - name: Host
                  value: gitlab.local
            periodSeconds: 10
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /-/health
              port: http
              httpHeaders:
                - name: Host
                  value: gitlab.local
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 6
          volumeMounts:
            - name: data
              mountPath: /etc/gitlab
              subPath: config
            - name: data
              mountPath: /var/log/gitlab
              subPath: logs
            - name: data
              mountPath: /var/opt/gitlab
              subPath: data
            - name: shm
              mountPath: /dev/shm
      volumes:
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: 256Mi
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 30Gi
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: gitlab
  namespace: gitlab
spec:
  ingressClassName: traefik
  rules:
    - host: gitlab.local
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: gitlab
                port:
                  number: 80
