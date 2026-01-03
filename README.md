PT: Esta é minha primeira arquitetura de solução na AWS.

Descrição do Projeto: Este projeto apresenta o design e a implementação de uma arquitetura em nuvem seguindo as melhores práticas do AWS Well-Architected Framework. O objetivo foi criar um ambiente altamente seguro, disponível e escalável, ideal para sistemas críticos como ERPs, portais acadêmicos ou plataformas de telemedicina.

Destaques Técnicos:

Segurança em Camadas (Defesa em Profundidade): Implementação de sub-redes públicas e privadas para isolamento de recursos, proteção de borda com AWS WAF e inspeção de tráfego via Security Groups e NACLs.

Alta Disponibilidade e Resiliência: Estrutura distribuída em múltiplas Zonas de Disponibilidade (Multi-AZ), utilizando um Application Load Balancer (ALB) e Auto Scaling Groups para garantir que a aplicação responda automaticamente a variações de tráfego e falhas de instâncias.

Otimização de Performance: Uso de Amazon CloudFront para entrega de conteúdo de baixa latência e S3 Gateway Endpoints para garantir que a comunicação com o armazenamento de objetos permaneça dentro da rede privada da AWS, reduzindo custos e aumentando a segurança.

Infraestrutura como Código (IaC): Todo o ambiente foi provisionado e versionado utilizando Terraform, garantindo a imutabilidade e a facilidade de replicação da infraestrutura.

Monitorização Proativa: Integração com Amazon CloudWatch para recolha de métricas e alarmes, permitindo uma resposta rápida a incidentes operacionais.

Principais Aprendizagens: Durante este desafio, foquei-me na separação de responsabilidades entre as camadas de rede e na aplicação do princípio do menor privilégio através do AWS IAM, garantindo que cada componente tenha apenas as permissões estritamente necessárias.

EN: This is my first solution architecture on AWS.

Project Overview: This project showcases the design and implementation of a cloud architecture following the AWS Well-Architected Framework best practices. The primary goal was to create a highly secure, available, and scalable environment, ideal for mission-critical systems such as ERPs, Academic Portals, or Telemedicine platforms.

Technical Highlights:

Layered Security (Defense in Depth): Implemented public and private subnets for resource isolation, edge protection using AWS WAF, and granular traffic control via Security Groups and NACLs.

High Availability & Resilience: Distributed structure across multiple Availability Zones (Multi-AZ), utilizing an Application Load Balancer (ALB) and Auto Scaling Groups to ensure the application automatically responds to traffic fluctuations and instance failures.

Performance Optimization: Leveraged Amazon CloudFront for low-latency content delivery and S3 Gateway Endpoints to ensure communication with object storage remains within the AWS private network, reducing costs and enhancing security.

Infrastructure as Code (IaC): The entire environment was provisioned and versioned using Terraform, ensuring immutability, consistency, and easy replication of the infrastructure.

Proactive Monitoring: Integrated with Amazon CloudWatch for metric collection and alarming, enabling rapid response to operational incidents.

Key Takeaways: In this challenge, I focused on the separation of concerns across network layers and the enforcement of the "Principle of Least Privilege" using AWS IAM, ensuring each component has only the strictly necessary permissions.

image
